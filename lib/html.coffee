module.exports =
  browser:
    noPreview: true
    ext: 'htmlp'
    hyperLive: true
    quickPreview: true
    exe: (src,options,data,fileName,quickPreview,hyperLive,editor,view)->

      if options['pp-url']
        htmlURL: options['pp-url']
      else
        if quickPreview or hyperLive
          lines = src.split('\n')
          src = lines.join('<br/>')
          html: """
            <pre style="word-wrap: break-word; white-space: pre-wrap;">
            #{src}
            </pre>
            """
        else
          htmlURL: fileName
