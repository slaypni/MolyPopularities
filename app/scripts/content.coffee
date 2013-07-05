# require hapt.js, underscore.js

_settings = null

callbg = (cb, fnname, args...) ->
    chrome.runtime.sendMessage {type: 'call', fnname: fnname, args: args}, (response) ->
        cb?(response)

callbgcb = (cb, fnname, args...) ->
    chrome.runtime.sendMessage {type: 'callWithCallback', fnname: fnname, args: args}, (response) ->
        cb?(response)
        
haptListen = (cb) ->
    hapt.listen( (keys, event) ->
        if not (event.target.isContentEditable or event.target.nodeName.toLowerCase() in ['textarea', 'input', 'select'])
            return cb(keys, event)
        return true
    , window, true, [])

chrome.runtime.sendMessage {type: 'getSettings'}, (settings) ->
    _settings = settings

    hapt_listener = haptListen (keys_) ->
        keys = keys_.join(' ')
        if keys in (binding.join(' ') for binding in _settings.bindings.toggle_popularities)
            Popularities.get().toggle()
        return true

    Popularities.get().show() if _settings.do_show_automatically

chrome.runtime.onMessage.addListener (message, sender, sendResponse) ->
    switch message
        when 'togglePopularities'
            Popularities.get().toggle()

class Popularities
    instance = null

    # get singleton instance
    @get: ->
        instance ?= new _Popularities

    class _Popularities
        PANEL_CLASS_NAME = 'moly_popularities_panel'
        BACK_PANEL_ID = 'moly_popularities_backpanel'
        BOX_CLASS_NAME = 'moly_popularities_box'
        FACEBOOK_LIKE_CLASS_NAME = 'moly_popularities_facebook_like'
        FACEBOOK_SHARE_CLASS_NAME = 'moly_popularities_facebook_share'
        TWITTER_TWEET_CLASS_NAME = 'moly_popularities_twitter_tweet'
        HATENA_BOOKMARK_CLASS_NAME = 'moly_popularities_hatena_bookmark'
        Z_INDEX_MAX = 2147483647

        constructor: ->
            @backpanel = null
            @popularity_requests = {}
            @memo = {}

            window.addEventListener 'scroll', (e) =>
                @show() if @backpanel?

        show: =>
            existing_targets = null
            if not @backpanel?
                @backpanel = document.createElement('div')
                @backpanel.id = BACK_PANEL_ID
                document.querySelector('body').appendChild(@backpanel)
            else
                existing_targets = Array.prototype.slice.call(@backpanel.children, 0).map (panel) => panel.moly_popularities.target  # somehow, this map cannot be written by list comprehensions

            isVisible = (e) =>
                return (e.offsetWidth > 0 or e.offsetHeight > 0) and window.getComputedStyle(e).visibility != 'hidden'

            isInsideDisplay = (e) =>
                pos = e.getBoundingClientRect()
                isInsideX = -1 * e.offsetWidth <= pos.left < (window.innerWidth or document.documentElement.clientWidth)
                isInsideY = -1 * e.offsetHeight <= pos.top < (window.innerHeight or document.documentElement.clientHeight)
                return isInsideX and isInsideY

            targets = Array.prototype.slice.call(document.querySelectorAll('a'), 0)
            targets = _.difference(targets, existing_targets) if existing_targets?
            targets = (e for e in targets when isVisible(e) and isInsideDisplay(e) and (e.href?.indexOf('http://') == 0 or e.href?.indexOf('https://') == 0))

            createPanel = (target) =>
                panel = document.createElement('div')
                panel.className = PANEL_CLASS_NAME
                href = target.href
                panel.moly_popularities =
                    target: target
                    href: href
                    
                appendBox = (className) =>
                    box = document.createElement('div')
                    box.className = className
                    panel.appendChild(box)
                    box.moly_popularities = 
                        bg: box.appendChild(document.createElement('div'))
                        count: box.appendChild(document.createElement('div'))
                    return box
                if _settings.do_show_facebook_like
                    panel.moly_popularities.facebook_like_box = appendBox("#{BOX_CLASS_NAME} #{FACEBOOK_LIKE_CLASS_NAME}")
                if _settings.do_show_facebook_share
                    panel.moly_popularities.facebook_share_box = appendBox("#{BOX_CLASS_NAME} #{FACEBOOK_SHARE_CLASS_NAME}")
                if _settings.do_show_twitter_tweet
                    panel.moly_popularities.twitter_tweet_box = appendBox("#{BOX_CLASS_NAME} #{TWITTER_TWEET_CLASS_NAME}")
                if _settings.do_show_hatena_bookmark
                    panel.moly_popularities.hatena_bookmark_box = appendBox("#{BOX_CLASS_NAME} #{HATENA_BOOKMARK_CLASS_NAME}")
                    
                @pushPopularityRequest href, (popularity) =>
                    setCount = (box, count) =>
                        if box? and count?
                            box.moly_popularities.count.textContent = count
                            box.style.width = box.moly_popularities.bg.style.width = box.moly_popularities.count.offsetWidth + 'px'
                    setCount(panel.moly_popularities.facebook_like_box, popularity.like_count)
                    setCount(panel.moly_popularities.facebook_share_box, popularity.share_count)
                    setCount(panel.moly_popularities.twitter_tweet_box, popularity.twitter_tweet_count)
                    setCount(panel.moly_popularities.hatena_bookmark_box, popularity.hatena_bookmark_count)

                panel.addEventListener 'mouseover', (e) =>
                    panel.style.zIndex = Z_INDEX_MAX

                panel.addEventListener 'mouseout', (e) =>
                    panel.style.zIndex = panel.moly_popularities.zIndex
                    
                return panel

            targets.reverse()
            panels = for target in targets
                panel = createPanel(target)
                @backpanel.appendChild(panel)
                panel.style.zIndex = panel.moly_popularities.zIndex = Z_INDEX_MAX - @backpanel.childElementCount
                setPosition = =>
                    PANEL_MARGIN = 1
                    offset = (e) =>
                        pos = e.getBoundingClientRect()
                        return {left: pos.left + window.scrollX, top: pos.top + window.scrollY}
                    {left: left, top: top} = offset(panel.moly_popularities.target)
                    switch _settings.panel_position
                        when 'outer right'
                            left += panel.moly_popularities.target.offsetWidth + PANEL_MARGIN
                        when 'outer bottom'
                            top += panel.moly_popularities.target.offsetHeight + PANEL_MARGIN
                    panel.style.left = '' + _.min([_.max([left, 0]), document.documentElement.scrollWidth - panel.offsetWidth]) + 'px'
                    panel.style.top = '' + _.min([_.max([top, 0]), document.documentElement.scrollHeight - panel.offsetHeight]) + 'px'
                setPosition()
                panel

            @fetchPopularityRequests()
                    

        hide: =>
            if not @backpanel? then return
            document.querySelector('body').removeChild(@backpanel)
            @backpanel = null
            @clearPopularityRequests()

        toggle: =>
            if @backpanel? then @hide() else @show()

        pushPopularityRequest: (url, cb) =>
            @popularity_requests[url] ?= []
            @popularity_requests[url].push(cb)

        fetchPopularityRequests: =>
            popularity_requests = @popularity_requests
            @popularity_requests = {}
            
            dispatchMemo = (type, urls) =>
                @memo[type] ?= {}
                for url in _.intersection(urls, _.keys(@memo[type]))
                    for cb in popularity_requests[url]
                        cb(@memo[type][url])

            urls = _.keys(popularity_requests)
            urls.reverse()
                        
            getFacebookPopularities = =>
                type = 'getFacebookPopularities'
                dispatchMemo(type, urls)
                chrome.runtime.sendMessage {
                    type: type
                    urls: _.difference(urls, _.keys(@memo[type]))
                    }, (results) =>
                        for result in results
                            if popularity_requests?
                                url = result['url']
                                @memo[type][url] = result
                                for cb in popularity_requests[url]
                                    cb(result)
            getFacebookPopularities() if _settings.do_show_facebook_like or _settings.do_show_facebook_share

            getPopularity = (type) =>
                dispatchMemo(type, urls)
                for url in _.difference(urls, _.keys(@memo[type]))
                    chrome.runtime.sendMessage {
                        type: type
                        url: url
                        }, (result) =>
                            if popularity_requests?
                                url = result.url
                                @memo[type][url] = result
                                for cb in popularity_requests[url]
                                    cb(result)
            getPopularity('getTwitterPopularity') if _settings.do_show_twitter_tweet
            getPopularity('getHatenaPopularity') if _settings.do_show_hatena_bookmark

        clearPopularityRequests: =>
            @popularity_requests = {}
