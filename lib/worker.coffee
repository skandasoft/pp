debugger
# console.log 'in the worker.js'
process.on 'message', (data)->
  debugger
  console.log('@obj',args)
  process.send('foo')
  # @obj.program @obj.args,@obj.options
  # process.kill('SIGHUP')

# process.stdout.on 'data',(data)->
#   console.log data
#   debugger
  # @obj.editor.insertText data.toString()

process.stderr.on 'data',(data)->
  debugger
  console.log data
  # @obj.editor.insertText data.toString()
