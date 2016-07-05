path = require 'path'
_ = require 'lodash'
uuid = require 'node-uuid'
jQuery = require 'jquery'
loophole = require './eval'
{CompositeDisposable,BufferedProcess} = require 'atom'
PPError = (@name,@message)->
PPError.prototype = new Error()
QuickView = require './quick-view'

module.exports =
  subscriptions: null

  config:
    require:
      title: 'NPM/Require'
      type: 'array'
      default:['./coffeeToJs']

    'coffee-types':
      title: 'Coffee File Types'
      type: 'array'
      default: []

    'coffee-cli-args':
      title: 'Coffee CLI Arguments'
      type: 'array'
      default: ['-e']

    'coffee-args':
      title: 'Coffee Arguments'
      type: 'array'
      default: []

    cursorFocusBack:
      default: true
      type: 'boolean'
      title: 'Set Cursor Focus Back'

    liveMilliseconds:
      title: 'MilliSeconds'
      type: 'number'
      default: 1200
      min: 600

    promptForSave:
      title: 'Prompt for save for previewed pane'
      type: 'boolean'
      default: false

  liveOff: ->
        for editor in @editors
          for key,ele of editor
            editor[key].dispose()
        @pp.setLive()

  activate: (state) ->
    # Events subscribed to in atom's system can be easily cleaned up with a CompositeDisposable
    @subscriptions = new CompositeDisposable
    @previews = []
    @editors = {}
    @processes = []
    @defaults = {}
    requires = atom.config.get('pp.require')
    atom.commands.add 'atom-text-editor', 'pp:preview': => @compile()
    atom.commands.add 'atom-text-editor', 'pp:liveOff': => @liveOff()
    atom.commands.add 'atom-text-editor', 'pp:killAll': => @killProcesses()
    @addPreviews(requires,false)

    idx = null
    itemSets = atom.contextMenu.itemSets
    contextMenu = _.find itemSets, (item,itemIdx)->
                    idx = itemIdx
                    item.items[0]?.command is 'pp:preview'

    if contextMenu?
      itemSets.splice idx,1
      itemSets.unshift contextMenu

    atom.contextMenu.itemSets = itemSets

    atom.workspace.onDidChangeActivePaneItem (activePane)=>
      return unless activePane
      @pp?.showStatusBar activePane
      subscribe?.dispose?()
      subscribe = activePane.onDidChangeGrammar?  (grammar)->
        _this.pp?._id = null
        _this.pp?.showStatusBar activePane,true

    atom.workspace.onDidDestroyPaneItem (pane)=>
          if @editors
            for key,ele of @editors[pane.item.id]
              @editors[pane.item.id][key].live?.dispose?()
              @editors[pane.item.id][key].hyperLive?.dispose?()
            delete @editors[pane.item.id]

  setLiveListener: (editor,_id,clicks)->
      status = @getStatus(editor,_id)
      if clicks is 1
        if status.live?.disposalAction or status.hyperLive?.disposalAction
          status.live?.dispose?()
          status.hyperLive?.dispose?()
        else
          status.live = editor.onDidSave  =>
                @compile(editor,_id)
        @editors[editor.id][_id] = status
        @compile(editor,_id)
      else
        editor.buffer.stoppedChangingDelay = atom.config.get('pp.liveMilliseconds')
        status.live?.dispose?()
        status.hyperLive = editor.onDidStopChanging =>
              @compile(editor,_id)
        @editors[editor.id][_id] = status
        @compile(editor,_id)

  consumeStatusBar: (statusBar)->
    @statusBar = statusBar
    {PPStatusView} = require './pp-status-view'
    editor = atom.workspace.getActiveTextEditor()
    @pp = new PPStatusView(@,editor)
    @pp.showStatusBar editor

  getPreviews: (editor,ext=@getExt(editor))->
    grammar = editor.getGrammar()
    previews = _.filter @previews, (preview)->
              return true unless (preview.fileTypes.length or preview.names.length or preview.scopeNames.length)
              return true if ext in preview.fileTypes
              # if it is not available
              for name in preview.names
                return true if name in grammar.name
              for scopeName in preview.scopeNames
                return true if scopeName in grammar.scopeName

              for fileType in preview.fileTypes
                return true if fileType in grammar.fileTypes
    throw new PPError 'alert','Set the Grammar for the Editor' unless previews.length
    previews

  getExt: (editor)->
    editorPath = editor.getPath()
    ext = path.extname(editorPath)[1...]

  fillStatus: (preview)->
    status = {}
    status._id = preview._id
    status.name = preview.name
    if preview.viewClass
      if preview.viewArgs
        preview.vw = new preview.viewClass(preview.viewArgs)
      else
        preview.vw= new preview.viewClass
      status.vw = preview.vw
    status

  getEnum: (editor)->
    ext = @getExt(editor)
    @defaults[ext].enum

  getStatus: (editor,_id)->
    _id = _id or @editors[editor.id]?.current
    status =  @editors[editor.id]?[_id] if _id
    return status if status
    if _id
      preview = _.find @previews, (preview)->
                    preview._id is _id
      status = @fillStatus(preview)
      status.enum = @getEnum(editor)
      @setCurrentStatus(editor,status)
      return status
    @getDefaultStatus(editor)

  setCurrentStatus: (editor,preview)->
    if @editors[editor.id]?[preview._id]
      return @editors[editor.id]?[preview._id]
    status = jQuery.extend {}, preview
    unless @editors[editor.id]
      @editors[editor.id] = {}
    @editors[editor.id][status._id] = status
    @editors[editor.id].current = status._id
    return status

  getDefaultStatus: (editor,fresh)->
    ext = @getExt(editor) or ''
    if fresh or not @defaults[ext]
      previews = @getPreviews editor,ext
      throw new PPError 'alert','No Previews Available' if previews.length is 0
      @defaults[ext] = @fillStatus previews[0],editor
      @defaults[ext].enum = true if previews.length > 1
    @setCurrentStatus(editor,@defaults[ext])

  compilePath: (path,_id)->
      panes = atom.workspace.getPaneItems()
      ed = atom.workspace.paneForURI(path)?.getItems()?.find (pane)-> pane.getURI() is path
      # ed  = panes.find (pane)->
      #         return if pane.constructor.name is 'HTMLEditor'
      #         pane.getURI() is path or "file:///"+pane.getURI() is path
      if ed
        @compile(ed,_id)
      else
        if path.startsWith('file:///')
          path = path.split('file:///')[1]
        atom.workspace.open(path)
                      .then (vw)=>
                            @compile(vw,_id)

  compile: (editor = atom.workspace.getActiveTextEditor(),_id)->

    status = @getStatus(editor,_id)
    @editors[editor.id].current = status._id
    {text,fpath,quickPreview} = @getText editor
    preview = _.find @previews,{_id:status._id}
    settings = @project?.props?.settings?[preview.fname] or {}
    options = jQuery.extend {},settings['pp-options'] ,@getContent('options',text)
    data = jQuery.extend {},settings['pp-data'],@getContent('data',text)
    @previewPane(preview,text,options,data,fpath,quickPreview,status.hyperLive?.disposalAction,editor,_id)

  killProcesses: ->
    for proc in @processes
      proc.kill()


  runProgram: (program,code,fpath, args, options,preview, editor) ->
    workerFile = "#{atom.packages.getActivePackage('pp').path}\\lib\\#{program}"
    onFinish = =>

    stdout  = (output) =>
      editor.insertText output

    stderr  = (output) =>
      editor.insertText output

    exit =  =>
      duration = (@startTime  - new Date())/1000
      switch
        when duration > 3600
          editor.insertText("[Completed in #{duration/3600} hrs]")
        when duration > 60
          editor.insertText("[Completed in #{duration/60} minutes]")
        else
          editor.insertText("[Completed in #{duration} seconds]")

      # process to be removed once the process get complete
      delete @processes[preview._id]
      compileTo = @pp.compileTo
      compileTo.text compileTo.text().replace('(kill)','')
    args = [workerFile,fpath]
    options = {
      stdio: 'pipe'
    }
    command = 'node'
    @startTime = new Date()
    coffee = require('coffee-script')
    js = coffee.compile(code)
    console.log js
    vm = require('vm')
    context = vm.createContext({
        require: require,
        # register:require('coffee-script/register'),
        console: console })
    vm.runInContext(js,context, fpath)

    # child = new BufferedProcess {command, args, options, stdout, stderr, exit}
    # # keep track of all process
    # @processes[preview._id] = child
    # # # update the status bar text add (kill)
    # @pp.compileTo.text   @pp.compileTo.text() + "(kill)"
    # child.process.stdin.write(code)
    # child.process.stdin.end()


    # cp = require 'child_process'
    # # child = cp.fork workerFile
    # # atom = require('atom-shell');
    # child = cp.spawn atom,["file://c/sub.js"]
    # #    child = cp.fork "./sub.js",[] ,{cwd:"file:c://"} #  "#{atom.packages.getActivePackage('pp').path}"}
    # # ,{cwd:__dirname}, (err,stdout,stderr)->
    # #   debugger
    # #   console.log 'stdout'
    # #   console.log 'std'
    # # console.log   workerFile
    # # child = cp.fork workerFile
    # # console.log 'seinding to the child'
    # # # child.send {program,args,options,preview,editor}
    # # debugger
    # child.on 'message', (data)->
    #   # debugger
    #   console.log 'received mes',data
    #
    # child.send('hlloo')

    # n.on 'message', (m) ->
    #   console.log('PARENT got message:', m);
    #
    # n.send({ hello: 'world' });
  runCommand: (command, args, options,preview, editor) ->

    onFinish = =>

    stdout  = (output) =>
      editor.insertText output

    stderr  = (output) =>
      editor.insertText output

    exit =  =>
      duration = (@startTime  - new Date())/1000
      switch
        when duration > 3600
          editor.insertText("[Completed in #{duration/3600} hrs]")
        when duration > 60
          editor.insertText("[Completed in #{duration/60} minutes]")
        else
          editor.insertText("[Completed in #{duration} seconds]")

      # process to be removed once the process get complete
      delete @processes[preview._id]
      compileTo = @pp.compileTo
      compileTo.text compileTo.text().replace('(kill)','')

    child = new BufferedProcess {command, args, options, stdout, stderr, exit}
    # update the status bar text add (kill)
    @startTime = new Date()
    @pp.compileTo.text   @pp.compileTo.text() + "(kill)"
    # keep track of all process
    @processes[preview._id] = child

  previewPane: (preview,text,options,data,fpath,quickPreview,live,editor,_id)->
    # grammar = if not err then preview.ext  else syntax = editor.getGrammar()
    syntax = atom.grammars.selectGrammar(preview.ext)
    view = undefined
    compile = =>
      try
        result = preview.exe(text,options,data,fpath,quickPreview,live,editor,view)
        unless result
          view?.destroy()
          return true
        formatResult = (res)=>
          if res.text or typeof res is 'string' or res.code
            @previewText(editor,view,res.text  or res.code or res)
          if res.command
            @runCommand res.command, res.args ,res.options or options,preview,view
          if res.program
            @runProgram res.program,text,fpath, res.args,res.options or options, preview,view

          if res.html or res.htmlURL
            view?.destroy()
            uri = res.htmlURL or "browser-plus~#{preview.name}~#{preview._id}://#{editor.getURI()}"
            pane = atom.workspace.paneForURI(uri)
            if pane
              htmlEditor = pane.getItems()?.find (itm)-> itm.getURI() is uri
              htmlEditor.setText(res.html) if res.html
              pane = atom.workspace.paneForItem htmlEditor
              pane.setActiveItem(htmlEditor)
              # htmlEditor.refresh()
            else
              atom.workspace.open uri,{src:res.html,split:@getPosition(editor),orgURI:fpath,_id:_id}

        if result.promise
          result.done (res)=>
            formatResult(res)
          result.fail (text)->
            e = new Error()
            e.name = 'console'
            e.message = text
            throw e
        else
          formatResult(result)
      #
      catch e
        console.log e.message
        if e.name is 'alert'
          alert e.message
        else
          if e.location
            {first_line} = e.location
            error = text.split('\n')[0...first_line].join('\n')
          error += '\n'+e.toString().split('\n')[1..-1].join('\n')+'\n'+e.message
          @previewText editor,view,error,true

    if preview.noPreview or preview.browserPlus
      compile()
    else

      if quickPreview
        unless @qView
          @qView = new QuickView(title,text,syntax)
          atom.workspace.addBottomPanel item: @qView
        else
          @qView.editor.setText('')
        view = @qView.showPanel(text,syntax)
        view.setGrammar syntax if syntax
        compile()
      else
        split = @getPosition editor
        title = editor.getTitle()
        if preview.ext
          title = title.substr(0, title.lastIndexOf('.'))
          title = "#{title}.#{preview.ext}~pp~#{preview.name}~#{preview._id}.#{preview.ext}"
        else
          title = "#{title}.~pp~#{preview.name}~#{preview._id}"

        atom.workspace.open title,
                          searchAllPanes:true
                          split: split
                          # src: text
                .then (vw)=>
                      view = vw
                      vw.shouldPromptToSave = ->
                        atom.config.get('pp.promptForSave')

                      view.setText('')
                      view.disposables.add editor.onDidDestroy =>
                        view.destroy()
                      view.setGrammar syntax if syntax
                      # view.moveToTop()
                      compile()

  previewText: (editor,view,text,err)->
    if view
      if err
        view.emitter.emit 'did-change-title', "#{view.getTitle()}.err"
        syntax = editor.getGrammar()
        view.setGrammar(syntax)

      view.setText(text)
      view.moveToTop()
    activePane = atom.workspace.paneForItem(editor)
    activePane.activate() if atom.config.get('pp.cursorFocusBack')

  consumeProjectManager: (PM) ->
    PM.projects.getCurrent (@project) =>
      # if project

  consumeBrowserPlus: (@bp) ->


  provideAddPreview: ->
       @addPreviews.bind(@)

  addPreviews: (requires,pkg=true)->
    if pkg
      if requires.deactivate
        return
      # pkage = _.find atom.packages.loadedPackages,(pkg)->
      #   pkg.mainModulePath is module.id
      # return unless pkage
      # requires = [].push(requires) unless $.isArray(requires)
      return unless requires['pkgName']
      requires = [requires]
    _ids = []
    for req in requires
      try
        preview = if pkg then req else require req
        fileTypes = preview['fileTypes'] or []
        names = preview['names'] or []
        scopeNames = preview['scopeNames'] or []
        for key,obj of preview
          continue if key in ['fileTypes', 'names', 'scopeNames','pkgName']
          continue unless obj['exe']
          obj.name = key unless obj.name
          if pkg
            obj.fname = "#{obj.name} (#{preview['pkgName']})"
          else
            obj.fname = "#{obj.name} (#{req})"
          obj.fileTypes =  (obj['fileTypes'] or []).concat fileTypes
          obj.names =  (obj['names'] or []).concat names
          obj.scopeNames =  (obj['scopeNames'] or []).concat scopeNames
          obj._id = uuid.v1()
          _ids.push obj._id
          @previews.push obj
        _ids
      catch e
        console.log 'check the requires setting in PP package',e
        atom.notifications.addInfo 'check the require settings in PP Package'+e

  getContent: (tag,text)->
      regex = new RegExp("<pp-#{tag}>([\\s\\S]*?)</pp-#{tag}>")
      match = text.match(regex)
      if match? and match[1].trim()
        data = loophole.allowUnsafeEval ->
            eval "(#{match[1]})"

  deactivate: ->
    @pp.destroy()
    @subscriptions.dispose()

  serialize: ->
    viewState = []
    for view in @views
      viewState.push if view.serialize?()
    previewState: @pp.serialize()
    viewState : viewState
    projectState: @project

  listen: ->
      textEditor = atom.workspace.getActiveTextEditor()
      if textEditor
        view = atom.views.getView(textEditor)
        atom.commands.dispatch(view,'pp:preview') if view

  getPosition: (editor)->
    activePane = atom.workspace.paneForItem(editor)
    paneAxis = activePane.getParent()
    paneIndex = paneAxis.getPanes().indexOf(activePane)
    orientation = paneAxis.orientation ? 'horizontal'
    if orientation is 'horizontal'
      if  paneIndex is 0 then 'right' else 'left'
    else
      if  paneIndex is 0 then 'down' else 'top'

  getText: (editor)->
    selected = editor.getSelectedText()
    quickPreview = true if selected
    fpath = editor.getPath() # unless ( selected or editor['preview-plus.livePreview'] )
    text = selected or editor.getText()

    if text.length is 0 or !text.trim() then throw new PPError 'alert','No Code to Compile' else { text, fpath, quickPreview}

  makeHTML: (obj = {})->
    cssURL = ''
    jsURL = ''
    obj.html or= ''
    obj.js or= ''
    obj.css or= ''
    for css in ( obj.cssURL or [] )
        cssURL = cssURL+ "<link rel='stylesheet' href='#{css}'>"

    for js in ( obj.jsURL or [] )
        jsURL = jsURL+ "<script src='#{js}''></script>"

    """
      <html>
        <head>
          #{obj.js}
          #{jsURL}
          #{obj.css}
          #{cssURL}
        </head>
        <body>
          #{obj.html}
        </body>
      </html>
      """
