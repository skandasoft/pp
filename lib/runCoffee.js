fpath = process.argv[2]
path = require('path')
process.stdin.setEncoding('utf8');
var code = '';
process.stdin.on('readable', function() {
  var chunk = process.stdin.read();
  if (chunk !== null) {
    code = code.concat(chunk)
  }
});

process.stdin.on('end', function() {
  coffee = require('coffee-script');
  js = coffee.compile(code)
  vm = require('vm');
  context = vm.createContext({
      require: require,
      register:require('coffee-script/register'),
      console: console,
      module:module,
      __filename: fpath
  });
  vm.runInContext(js,context, fpath);
});
