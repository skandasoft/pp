# <pp-options>{bare:true}</pp-options>
coffee = require 'coffee-script'
jQuery = require 'jquery'
loophole = require './eval'
fs = require 'fs'
module.exports =

  fileTypes: do ->
    types = atom.config.get('pp.coffee-types') or []
    types.concat ['coff','coffee'] #filetypes against which this compileTo Option will show

  names: do ->
    names = atom.config.get('pp.coffee-names') or []
    names.concat ['CoffeeScript (Literate)'] #filetypes against which this compileTo Option will show

  scopeNames: do ->
    scopes = atom.config.get('pp.coffee-scope') or []
    scopes.concat ['source.litcoffee'] #filetypes against which this compileTo Option will show

  # js:
  #   scopes: scopes.concat ['source.litcoffee'] #scopes this applicable for
  #   names: names.concat ['CoffeeScript (Literate)'] # name as in grammar this applicable for
  #   fileTypes: fileTypes.concat ['coffee'] #file Extensions this applicable for, No need for .
  #   ext: 'js' #extension of the resulting preview
  #   name: 'js' # name as it appears in the dropdown
  #   options: bare:true #default options to pass with the compiler
  #   hyperLive: true #on change to editor code will show preview updates
  #   quickPreview: true #quick preview of few lines
  #   # actual compile function
  #   # exe: (editor,fileName,src,quickPreview,hyperLive,params,previewPane)->
  #   exe: (src,options,data,fileName,quickPreview,hyperLive,editor)->
  #     text : coffee.compile src, options
  #   # scroll syncing option between source code and target possible through source maps
  #   scrollSync : ->

  js:
    ext: 'js'
    hyperLive: true
    quickPreview: true
    exe: (src,options,data,fileName,quickPreview,hyperLive,editor,view)->
      options.filename = fileName
      if quickPreview or hyperLive or fileName.indexOf '~pp~coffee~'
        text : coffee.compile src, options
      else
        dfd = new jQuery.Deferred()
        fs.readFile fileName,'utf-8',(err,data)=>
          if err
            console.log dfd.fail err
            text : coffee.compile src, options
          else
            dfd.resolve text: coffee.compile data, options
        dfd.promise()

  run:
    hyperLive: true
    quickPreview: true
    exe: (src,options={},data,fileName,quickPreview,hyperLive,editor,view)->

      if quickPreview or hyperLive or fileName.indexOf('~pp~')
        args = atom.config.get('pp.coffee-cli-args').concat(src)
        program: 'runCoffee.js'
        args: args
        # process: loophole.runCommand 'coffee', [args].concat(src),options,editor
      else
        args = atom.config.get('pp.coffee-args').concat(fileName)
        # process: loophole.runCommand 'coffee', [args].concat(fileName),options,view
        command: 'coffee'
        args: args

  html:
    hyperLive: true
    quickPreview: true
    ext: 'html'
    exe: (src,options={},data,fileName,quickPreview,hyperLive,editor,view)->
      options.filename = fileName
      coffeeSrc =  src
      unless (quickPreview or hyperLive or fileName.startsWith('browserplus~'))
        try
          coffeeSrc = fs.readFileSync(fileName,'utf-8').toString()
        catch e

      js = coffee.compile coffeeSrc, options
      js = "<script type='text/javascript'>#{js}</script>\n"
      atom.packages.getActivePackage('pp').mainModule.makeHTML
          js: js
          jsURL: data.js
          cssURL: data.css


  browser:
    hyperLive: true
    quickPreview: true
    browserPlus: true
    exe: (src,options={},data,fileName,quickPreview,hyperLive,editor,view)=>
      coffeeSrc =  src
      unless (quickPreview or hyperLive or fileName.startsWith('browserplus~'))
        try
          coffeeSrc = fs.readFileSync(fileName,'utf-8').toString()
        catch e
      js = coffee.compile coffeeSrc, options
      js = "<script type='text/javascript'>#{js}</script>"
      html: atom.packages.getActivePackage('pp').mainModule.makeHTML
              js: js
              jsURL: data.js
              cssURL: data.css
