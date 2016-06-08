{View,SelectListView} = require 'atom-space-pen-views'
$ = require 'jquery'
_ = require 'lodash'

class PPStatusView extends View
  @content: ->
    @div class:'pp-status inline-block', =>
      @span "Live",class:"live off ",outlet:"live", click:'toggleLive'
      @span class:"compileTo",outlet:"compileTo", click:'compile'
      @span "▼", class:"enums",outlet:"enums", click:'previewList'

  initialize: (@model,@editor)->
    @statusBarTile = @model.statusBar.addRightTile {item:@, priority:9999}
    @clicks = 0

  setLive: (live)->
    if @edStatus.live?.disposalAction
      @live.removeClass('off').removeClass('hyper').addClass('on')
    else if @edStatus.hyper?.disposalAction
      @live.removeClass('off').removeClass('on').addClass('hyper')
    else
      @live.removeClass('on').removeClass('hyper').addClass('off')

  setCompilesTo: (@editor)->
    return unless @editor
    @hide()
    try
      grammar = @editor.getGrammar?()
      return false unless grammar
      cache = @editor.id is @id
      @id = @editor.id

      @edStatus = @model.getEditorStatus(@editor,cache)
      return if $.isEmptyObject @edStatus
      unless cache
        @previews = @edStatus.previews
        @preview = @edStatus.preview
        @ext = @edStatus.ext
        @edStatus = @edStatus.edStatus
      return unless @edStatus.compileTo
      if @preview.viewClass
        @compileTo.empty().append @preview.vw
      else
        @compileTo.empty().text @edStatus.compileTo
      # else
      #   @compileTo.empty().append compileToView
      @show()
      @setLive()
      if @edStatus.enum
        @enums.show()
      else
        @enums.hide()
    catch e
      console.log 'Not a Preview-Plus Editor',e

  compile: ->
    @model.compile(@editor,@preview)

  setToggleLive: (click)->
    @model.setLiveListener(@editor,click)
    @setLive()

  toggleLive: (evt)->
    if @model.processes[@preview._id]
      @model.processes[@preview._id].kill()
      @compileTo.replace('(kill)','')
      return true
    @clicks++
    if @clicks is 1
      @timer = setTimeout =>
        @clicks = 0
        @setToggleLive(1)
      ,300
    else
      @clicks = 0
      if ( typeof @preview.hyperLive is 'boolean' and @preview.hyperLive ) or (typeof @preview.hyperLive is 'function' and @preview.hyperLive())
        @setToggleLive(2)
      else
        atom.notifications.addInfo('HyperLive Not available')

      clearTimeout @timer

  previewList: ->
    new CompilerView @previews,@

  updateCompileTo: (item)->
    @preview = item
    @edStatus.compileTo = item.name
    if item.vw
      item.statusView = item.vw.clone(true) unless item.statusView
      @compileTo.empty().append item.statusView
    else
      @compileTo.empty().text @edStatus.compileTo
    @model.compile(@editor,@preview)

  show: ->
    super

  hide: ->
    super
  destroy: ->

class CompilerView extends SelectListView
  initialize: (items,@statusView)->
    super
    @addClass 'overlay from-top'
    @setItems items
    atom.workspace.addModalPanel item:@
    @focusFilterEditor()
    # if @statusView.compileTo.children()?.length > 0
    #   @selectItemView @list.find("li").has('span')
    # else
    #   compileTo = @statusView.compileTo.text()
    #   @selectItemView @list.find("li:contains('#{compileTo}')")

  viewForItem: (item)->
    if item.viewClass
      li = $("<li><span class='pp-space'></span></li>")
      if item.viewArgs
        item.vw = new item.viewClass(item.viewArgs)
      else
        item.vw = new item.viewClass
      li.append item.vw
      item.vw.selectList = @
    else
      li = $("<li>#{item.fname}<span class='pp-space'></span></li>")
    # li = $("<li>#{item.fname}</li>")
    if item.default
      radio = $("<span class='pp-default mega-octicon octicon-star on'></span>")
    else
      radio = $("<span class='pp-default mega-octicon octicon-star'></span>")
    fn = (e)=>
      $(`this `).closest('ol').find('span').removeClass('on')
      $(`this `).addClass('on')
      for preview in @statusView.previews
        preview.default = false
      item.default = true
      e.stopPropagation()
      return false
    radio.on 'mouseover', fn
    li.append(radio)
    return li
    # "<li>#{item.fname} <\li>"
    # if typeof item is 'string'
    #   "<li>#{item}</li>"
    # else
    #   $li = $('<li></li>').append item.element
    #   $li.data('selectList',@)
      # item
  confirmed: (item)->
    @statusView.updateCompileTo(item)
    # if item.vw
    #   for i in [1..10000]
    #     console.log i
    # else
    @cancel()

  cancelled: ->
    @parent().remove()

module.exports = { PPStatusView, CompilerView }
