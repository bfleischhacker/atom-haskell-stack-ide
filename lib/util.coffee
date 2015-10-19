{Range, Point, Directory} = require 'atom'
{delimiter} = require 'path'
Temp = require('temp')
FS = require('fs')

module.exports = Util =
  debug: (messages...) ->
    if atom.config.get('haskell-stack-ide.debug')
      console.log "haskell-stack-ide debug:", messages...
      # console.trace "haskell-stack-ide trace:"

  getRootDir: (buffer) ->
    [dir] = atom.project.getDirectories().filter (dir) ->
      dir.contains(buffer.getUri())
    res = dir ? atom.project.getDirectories()[0]
    if res?.getPath?() is 'atom://config'
      res = null
    unless res?.isDirectory?()
      res = buffer.file?.getParent?() ? new Directory ''
    return res

  getProcessOptions: (rootPath) ->
    Util.debug "getProcessOptions(#{rootPath})"
    env = {}
    for k, v of process.env
      env[k] = v
    apd = atom.config.get('haskell-stack-ide.additionalPathDirectories')
          .concat process.env.PATH.split delimiter
    if rootPath
      apd.unshift "#{rootPath}/.cabal-sandbox/bin"
    env.PATH = "#{apd.join(delimiter)}"
    Util.debug "PATH = #{env.PATH}"
    options =
      cwd: rootPath
      env: env

  getSymbolInRange: (regex, buffer, crange) ->
    if crange.isEmpty()
      {start, end} = buffer.rangeForRow crange.start.row
      crange2 = new Range(crange.start, crange.end)
      buffer.backwardsScanInRange regex, new Range(start, crange.start),
        ({range, stop}) ->
          crange2.start = range.start
      buffer.scanInRange regex, new Range(crange.end, end),
        ({range, stop}) ->
          crange2.end = range.end
    else
      crange2 = crange

    symbol: buffer.getTextInRange crange2
    range: crange2

  toRange: (pointOrRange) ->
    if pointOrRange instanceof Point
      new Range pointOrRange, pointOrRange
    else if pointOrRange instanceof Range
      pointOrRange
    else
      throw new Error("Unknown point or range class #{pointOrRange}")

  rangeToStackSpan: (range) -> return {
    spanFromLine: range.start.row + 1
    spanToLine: range.end.row + 1
    spanFromColumn: range.start.column + 1
    spanToColumn: range.end.column + 1
  }

  stackSpanToRange: (span) ->
    try
      startRow = span['spanFromLine'] - 1
      startCol = span['spanFromColumn'] - 1
      endRow = span['spanToLine'] - 1
      endCol = span['spanToColumn'] - 1
      return new Range [startRow, startCol], [endRow, endCol]
    catch error
      return null

  stackSpan: (buffer, range) ->
    span = Util.rangeToStackSpan(range)
    root = Util.getRootDir buffer
    rel = root.relativize(buffer.getPath())
    span['spanFilePath'] = rel
    return span

  withTempFile: (contents, func, suffix, opts) ->
    Temp.open
      prefix: 'haskell-stack-ide',
      suffix: suffix,
      (err, info) ->
        if err
          atom.notifications.addError "haskell-stack-ide: Error when writing
            temp. file",
            detail: "#{err}"
            dismissable: true
          opts.callback []
          return
        FS.writeSync info.fd, contents
        {uri, callback} = opts
        opts.uri = info.path
        opts.callback = (res) ->
          FS.close info.fd, -> FS.unlink info.path
          callback res.map (line) ->
            line.split(info.path).join(uri)
        func opts

  uuid: (a) =>
    if a?
      return (a^Math.random()*16>>a/4).toString(16)
    else
      return ([1e7]+-1e3+-4e3+-8e3+-1e11).replace(/[018]/g, Util.uuid)
