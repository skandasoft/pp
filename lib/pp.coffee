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

  activate: (state) ->
    # Events subscribed to in atom's system can be easily cleaned up with a CompositeDisposable
    @subscriptions = new CompositeDisposable
    @previews = []
    @editors = []
    @processes = []
    @defaults = {}
    requires = atom.config.get('pp.require')
    atom.commands.add 'atom-text-editor', 'pp:preview': => @compile()
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
      @previewStatus?.setCompilesTo activePane
      subscribe?.dispose?()
      subscribe = activePane.onDidChangeGrammar?  (grammar)->
        _this.previewStatus?.setCompilesTo activePane

    atom.workspace.onDidDestroyPaneItem (pane)=>
      _.remove @editors,(ed)->
                  return true if ed[pane.item.id]
      # console.log @editors


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


  setLiveListener: (editor,clicks)->
      editorStatus = @getEditorStatus(editor)

      if clicks is 1
        if editorStatus.live?.disposalAction or editorStatus.hyper?.disposalAction
          editorStatus.live?.dispose()
          editorStatus.hyper?.dispose()
        else
          editorStatus.live = editor.onDidSave @listen
        @compile(editor)
      else
        editor.buffer.stoppedChangingDelay = atom.config.get('pp.liveMilliseconds')
        editorStatus.live?.dispose()
        editorStatus.hyper = editor.onDidStopChanging @listen
        @compile(editor)

  consumeStatusBar: (statusBar)->
    @statusBar = statusBar
    {PPStatusView} = require './pp-status-view'
    editor = atom.workspace.getActiveTextEditor()
    @previewStatus = new PPStatusView(@,editor)
    @previewStatus.setCompilesTo editor

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
    # throw new PPError 'alert','Set the Grammar for the Editor' unless previews.length
    previews
  getExt: (editor)->
    editorPath = editor.getPath()
    ext = path.extname(editorPath)[1...]

  getEditorStatus: (editor,cache=true)->
    try
      status = {}
      editorStatus = _.find @editors,(ed)->
                      return true if ed[editor.id]
      status = editorStatus[editor.id] if editorStatus
      unless cache and editorStatus
        ext = @getExt(editor)
        previews = @getPreviews editor,ext
        return {} if previews.length is 0
        unless editorStatus
          # preview = @getDefaultPreview(previews,ext)
          preview = @getDefault previews,ext
          status = { compileTo: preview.name }
          status._id = preview._id
          status.enum =  previews.length > 1
          obj = {}
          obj[editor.id] = status
          @editors.push obj
        else
          preview = _.find previews, {_id:status._id}

      if cache
        status
      else
        {edStatus: status,previews:previews,ext:ext,preview:preview}

    catch e
      console.log e,"No Preview-Plus Previews Available"

  getDefault: (previews,ext)->
    debugger
    return if previews?.length is 0
    unless @defaults[ext]?
      preview = _.find previews,@defaults[ext]
      @createPreview(preview)
    else
      @default[ext] = previews[0].name

  createPreview: (preview)->
      if preview.viewClass
        if preview.viewArgs
          preview.vw = new preview.viewClass(preview.viewArgs)
        else
          preview.vw = new preview.viewClass
      else
        preview.name

  getDefaultPreview: (previews,ext)->
    debugger
    return if previews?.length is 0
    unless @defaults[ext]?
      preview = _.find previews,@defaults[ext]
    else
      previews[0]

  compile: (editor = atom.workspace.getActiveTextEditor(),preview )->
    edStatus = @getEditorStatus(editor)
    previews = @getPreviews(editor)
    if preview
      edStatus._id = preview._id
    else
      preview = _.find previews,(preview)->
        return true if preview._id == edStatus._id
    {text,fpath,quickPreview} = @getText editor

    settings = @project?.props?.settings?[preview.fname] or {}
    options = jQuery.extend {},settings['pp-options'] ,@getContent('options',text)
    data = jQuery.extend {},settings['pp-data'],@getContent('data',text)
    @previewPane(preview,text,options,data,fpath,quickPreview,edStatus.hyper?.disposalAction,editor)

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
      compileTo = @previewStatus.compileTo
      compileTo.text compileTo.text().replace('(kill)','')
    args = [workerFile,fpath]
    options = {
      stdio: 'pipe'
    }
    command = 'node'
    @startTime = new Date()
    coffee = require('coffee-script');
    js = coffee.compile(code)
    console.log js
    vm = require('vm');
    context = vm.createContext({
        require: require,
        # register:require('coffee-script/register'),
        console: console    });
    vm.runInContext(js,context, fpath);

    # child = new BufferedProcess {command, args, options, stdout, stderr, exit}
    # # keep track of all process
    # @processes[preview._id] = child
    # # # update the status bar text add (kill)
    # @previewStatus.compileTo.text   @previewStatus.compileTo.text() + "(kill)"
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
      compileTo = @previewStatus.compileTo
      compileTo.text compileTo.text().replace('(kill)','')

    child = new BufferedProcess {command, args, options, stdout, stderr, exit}
    # update the status bar text add (kill)
    @startTime = new Date()
    @previewStatus.compileTo.text   @previewStatus.compileTo.text() + "(kill)"
    # keep track of all process
    @processes[preview._id] = child

  previewPane: (preview,text,options,data,fpath,quickPreview,live,editor)->
    # grammar = if not err then preview.ext  else syntax = editor.getGrammar()
    syntax = atom.grammars.selectGrammar(preview.ext)
    view = undefined
    compile = =>
      try
        result = preview.exe(text,options,data,fpath,quickPreview,live,editor,view)
        unless result
          view?.destroy()
          return true
        if result.text
          @previewText(editor,view,result.text)
        if result.promise
          promise.done (text)=>
            @previewText(editor,view,text)
          promise.fail (text)->
            e = new Error()
            e.name = 'console'
            e.message = text
            throw e
        if result.command
          @runCommand result.command, result.args ,result.options or options,preview,view
        if result.program
          @runProgram result.program,text,fpath, result.args,result.options or options, preview,view

        if result.html
          view?.destroy()
          uri = "browser-plus://preview~#{editor.getURI()}.htmlp"
          pane = atom.workspace.paneForURI(uri)
          if pane
            htmlEditor = pane.activeItem
            htmlEditor.setText(result.html)
          else
            @bp.open "#{editor.getURI()}.htmlp",result.html,@getPosition editor

        if result.htmlURL
          view?.destroy()
          uri = "#{editor.getURI()}.htmlp"
          pane = atom.workspace.paneForURI(uri)
          if pane
            htmlEditor = pane.activeItem
            htmlEditor.refresh()
          else
            @bp.open uri,null,@getPosition(editor),result.htmlURL
        activePane = atom.workspace.paneForItem(editor)
        activePane.activate() if atom.config.get('pp.cursorFocusBack')

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
    if preview.noPreview
      compile()
    else
      if editor.getSelectedText()
        unless @qView
          @qView = new QuickView(title,text,syntax)
          atom.workspace.addBottomPanel item: @qView
        else
          @qView.editor.setText('')
        view = @qView.showPanel(text,syntax)
        view.setGrammar syntax if syntax
        # ed = @qView.find('.editor')[0].getModel()
        # ed.setGrammar syntax if syntax
        compile()
      else
        split = @getPosition editor
        # ext = if err then "#{preview.ext}.err" else preview.ext
        if preview.ext
          title = "preview~#{editor.getTitle()}.#{preview.ext}"
        else
          title = "preview~#{editor.getTitle()}"
          title = title.substr(0, title.lastIndexOf('.'))
        atom.workspace.open title,
                          searchAllPanes:true
                          split: split
                          # src: text
                .then (vw)=>
                      view = vw
                      view.setText('')
                      view.disposables.add editor.onDidDestroy =>
                        view.destroy()
                      # view.setText(text)
                      view.setGrammar syntax if syntax
                      view.moveToTop()
                      # activePane = atom.workspace.paneForItem(editor)
                      # activePane.activate() if atom.config.get('pp.cursorFocusBack')
                      viewStatus = @getEditorStatus(view)
                      viewStatus.orgURI = editor.getURI()
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

  getContent: (tag,text)->
      regex = new RegExp("<pp-#{tag}>([\\s\\S]*?)</pp-#{tag}>")
      match = text.match(regex)
      if match? and match[1].trim()
        data = loophole.allowUnsafeEval ->
            eval "(#{match[1]})"


  getTextTag: (tag,text)->
      regex = new RegExp("<#{tag}>([\\s\\S]*?)</#{tag}>")
      match = text.match(regex)
      match[1].trim() if match?

  deactivate: ->
    @previewStatus.destroy()
    @subscriptions.dispose()

  serialize: ->
    viewState = []
    for view in @views
      viewState.push if view.serialize?()
    previewState: @previewStatus.serialize()
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
