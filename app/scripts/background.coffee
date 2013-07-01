x2js = new X2JS()

getFacebookPopularities = (urls, cb) ->
    if urls?.length == 0 then return
    req = new XMLHttpRequest()
    fields = ['url', 'like_count', 'share_count'].join(',')
    urls = (encodeURIComponent("\"#{url}\"") for url in urls).join(',')
    req.open('GET', "https://api.facebook.com/method/fql.query?query=select #{fields} from link_stat where url in (#{urls})", true)
    req.onload = ->
        res = x2js.xml_str2json(@responseText)
        if not res.error_response?
            cb(res.fql_query_response.link_stat)
    req.send()

getTwitterPopularity = (url, cb) ->
    req = new XMLHttpRequest()
    req.open('GET', "http://cdn.api.twitter.com/1/urls/count.json?url=#{encodeURIComponent(url)}", true)
    req.onload = ->
        res = JSON.parse(@responseText)
        cb({url: url, twitter_tweet_count: res.count})
    req.send()

getHatenaPopularity = (url, cb) ->
    req = new XMLHttpRequest()
    req.open('GET', "http://api.b.st-hatena.com/entry.count?url=#{encodeURIComponent(url)}", true)
    req.onload = ->
        count = parseInt("0#{@responseText}")
        cb({url: url, hatena_bookmark_count: count})
    req.send()


chrome.runtime.onMessage.addListener (request, sender, sendResponse) ->
    getFunction = ->
        obj = window
        for prop in request.fnname.split('.')
            obj = obj[prop]
        return obj

    switch request.type
        when 'call'
            fn = getFunction()
            response = fn.apply(this, request.args)
            sendResponse(response)
        when 'callWithCallback'
            fn = getFunction()
            fn.apply(this, request.args.concat(sendResponse))
        when 'getTab'
            sendResponse(sender.tab)
        when 'getSettings'
            storage.getSettings (settings) ->
                sendResponse(settings)
        when 'setSettings'
            storage.setSettings request.settings, (settings) ->
                sendResponse(settings)
        when 'getFacebookPopularities'
            getFacebookPopularities(request.urls, sendResponse)
        when 'getTwitterPopularity'
            getTwitterPopularity(request.url, sendResponse)
        when 'getHatenaPopularity'
            getHatenaPopularity(request.url, sendResponse)
            
    return true


chrome.browserAction.onClicked.addListener (tab) ->
    chrome.tabs.sendMessage(tab.id, 'togglePopularities')
