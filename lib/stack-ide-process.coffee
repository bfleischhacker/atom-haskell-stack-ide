{BufferedProcess, Range, Point, Emitter, CompositeDisposable} = require 'atom'
Util = require './util'
{extname} = require('path')
CP = require('child_process')

module.exports =
class StackIdeProcess
  backend: null
  processMap: null
  handlers: null
  genericHandlers: {
    'ResponseWelcome': @_handleResponseWelcome
    'ResponseLog': @_handleResponseLog
    'ResponseUpdateSession': @_handleUpdateSession
  }

  constructor: ->
    @processMap = new Map
    @handlers = new Map
    @disposables = new CompositeDisposable
    @disposables.add @emitter = new Emitter
    @bufferStatus = new WeakMap

  spawnProcess: (rootDir) =>
    return unless @processMap?
    proc = @processMap.get(rootDir.getPath())
    if proc?
      console.debug "Found running stack-ide instance for #{rootDir.getPath()}"
      clearTimeout proc.timer
      proc.timer = timer
      return proc.process
    options = {cwd: rootDir.getPath()}
    Util.debug "Spawning new stack-ide instance for #{rootDir.getPath()} with
          #{"options.#{k} = #{v}" for k, v of options}"
    stackPath = atom.config.get('haskell-stack-ide.stackPath')
    proc = CP.spawn(stackPath, ['ide', 'start'], options)
    @processMap.set rootDir.getPath(),
      root: rootDir
      process: proc
      timer: timer
      callbackQueues: {}
    timer = setTimeout (=>
      Util.debug "Killing stack-ide for #{rootDir.getPath()} due to inactivity"
      @killProcessForDir rootDir), 60 * 60 * 1000
    proc.stderr.on 'data', (data) => @handleError(data)
    proc.stdout.on 'data', (data) =>
      if data?
        data.toString().split("\n")
          .filter (d) -> d isnt ""
          .forEach (d) => @handleResponse(rootDir, d)
    proc.on 'error', (error) =>
      @handleError("failed to start stack ide: ${error}")
    proc.on 'close', (code) => @handleExit(rootDir, proc, code)
    return proc

  handleExit: (rootDir, proc, code) =>
    console.debug "stack-ide for #{rootDir.getPath()} ended with #{code}: #{err}"
    proc.stdin.end()
    @processMap.delete(rootDir.getPath())

  handleError: (data) =>
    console.debug "Recieved error from stack-ide #{data}"

  handleResponse: (rootDir, data) =>
    try
      json = JSON.parse data
      tag = json["tag"]
      contents = json["contents"]
      seq = json["seq"]
      if seq?
        {cb, ts} = @handlers.get seq
        if cb?
          #if the cb returns true, its finished
          if cb(contents)
            @handlers.delete seq
        else
          console.warn "Unexpected stack ide response seq id #{tag}: #{JSON.stringify(contents)}"
      else if @genericHandlers[tag]?
        @genericHandlers[tag](contents)
      else
        console.debug "Stack IDE Debug: #{data}"
    catch error
      console.error("error handling stack ide response #{error}: #{data}")

  _handleResponseWelcome: (contents) =>
    console.debug("Stack IDE started")
    @emitter.emit "backend-idle"

  _handleResponseLog: (contents) =>
    #console.debug("Stack IDE Log: #{contents}")

  _handleResponseUpdateSession: (contents) =>
    switch contents['tag']
      when "UpdateStatusProgress"
        @emitter.emit "backend-active"
      when "UpdateStatusDone"
        console.debug("finished updating")
        @emitter.emit "backend-idle"
      else console.warn("Unrecognized stack ide ResponseUpdateSession: #{contents['tag']}")


  runStackIdeCmd: (dir, command, contents, callback) =>
    contents = [] unless contents?
    uuid = Util.uuid()
    cmd = JSON.stringify({tag: command, contents: contents, seq: uuid })
    Util.debug "Trying to run stack-ide command in #{dir.getPath()}: #{cmd}"
    process = @spawnProcess(dir, @options)
    unless process
      Util.debug "Failed"
      return
    @handlers.set uuid, { ts: Date.now(), cb: callback }
    process.stdin.write "#{cmd}\n"
    @emitter.emit 'queue-idle'

  killProcess: =>
    return unless @stackIdeProcess?
    Util.debug "Killing all stackIdeProcesses processes"
    atom.project.getDirectories().forEach (dir) =>
      @killProcessForDir dir

  killProcessForDir: (dir) =>
    return unless @processMap?
    Util.debug "Killing ghc-modi process for #{dir.getPath()}"
    clearTimeout @processMap.get(dir.getPath())?.timer
    @processMap.get(dir)?.process.stdin?.end?()
    @processMap.get(dir)?.process.kill?()
    @processMap.delete(dir)

  killProcess: =>
    @backend.killProcess()

  # Tear down any state and detach
  destroy: =>
    Util.debug "StackIdeProcess destroying"
    @killProcess()
    @emitter.emit 'did-destroy'
    @emitter = null
    @disposables.dispose()
    @processMap = null

  onDidDestroy: (callback) =>
    @emitter.on 'did-destroy', callback

  onBackendActive: (callback) =>
    @emitter.on 'backend-active', callback

  onBackendIdle: (callback) =>
    @emitter.on 'backend-idle', callback

  onQueueIdle: (callback) =>
    @emitter.on 'queue-idle', callback

  queueCmd: (qn, o) =>
    @backend.run o

  runList: (rootPath, callback) =>

  runLang: (callback) =>

  runFlag: (callback) =>

  runBrowse: (rootPath, modules, callback) =>

  getTypeInBuffer: (buffer, crange, callback) =>
    console.debug("looking up type")
    crange = Util.toRange crange
    rootDir = Util.getRootDir(buffer)
    @runStackIdeCmd rootDir, 'RequestGetExpTypes', {
      spanFilePath:  rootDir.relativize(buffer.getPath())
      spanFromLine: crange.start.row + 1
      spanFromColumn: crange.start.column + 1
      spanToLine: crange.end.row + 1
      spanToColumn: crange.end.column + 1
    },
    (contents) =>
      console.debug "Result: #{contents}"
      range = crange
      type = undefined
      for [t, r] in contents
        startRow = r['spanFromLine'] - 1
        startCol = r['spanFromColumn'] - 1
        endRow = r['spanToLine'] - 1
        endCol = r['spanToColumn'] - 1
        trange = new Range [startRow, startCol], [endRow, endCol]
        if trange.containsRange(crange)
          type = t
          range = trange
          break
      console.debug "Type of range #{range}: #{type}"
      callback {range, type}

  getInfoInBuffer: (buffer, crange, callback) =>
    # crange = Util.toRange crange
    # {symbol, range} = Util.getSymbolInRange(/[\w.']*/, buffer, crange)
    #
    # @queueCmd 'typeinfo',
    #   interactive: true
    #   dir: Util.getRootDir(buffer)
    #   options: Util.getProcessOptions(Util.getRootDir(buffer).getPath())
    #   command: 'info'
    #   uri: buffer.getUri()
    #   text: buffer.getText() if buffer.isModified()
    #   args: ["", symbol]
    #   callback: (lines) ->
    #     text = lines.join('\n')
    #     text = undefined if text is 'Cannot show info' or not text
    #     callback {range, info: text}

  findSymbolProvidersInBuffer: (buffer, crange, callback) =>
    # crange = Util.toRange crange
    # {symbol} = Util.getSymbolInRange(/[\w']*/, buffer, crange)
    #
    # @queueCmd 'find',
    #   options: Util.getProcessOptions(Util.getRootDir(buffer).getPath())
    #   command: 'find'
    #   args: [symbol]
    #   callback: callback

  getSpanInfo: (buffer, crange, callback) =>
    # console.debug "getSpanInfo for #{buffer.getPath()}"
    # rootDir = Util.getRootDir(buffer)
    # @runStackIdeCmd rootDir, 'RequestGetSpanInfo',
    #   spanFilePath: buffer.getPath()
    #   spanFromLine: crange.start.row
    #   spanFromColumn: crange.start.column
    #   spanToLine: crange.end.row
    #   spanToColumn: crange.end.column,
    #
    #   (contents) => console.debug("SpanInfo #{JSON.stringify(contents)}")

  getLoadedModules: (buffer) =>
    dir = Util.getRootDir(buffer)
    @runStackIdeCmd dir, 'RequestGetLoadedModules', []

  updateSession: (buffer, callback) =>
    console.debug("requesting updated session")
    dir = Util.getRootDir(buffer)
    @runStackIdeCmd dir, 'RequestUpdateSession',
      [{"tag": "RequestSessionUpdate", "contents": []}],
      (contents) =>
        switch contents['tag']
          when "UpdateStatusProgress"
            @emitter.emit "backend-active"
          when "UpdateStatusDone"
            console.debug("finished updating")
            @emitter.emit "backend-idle"
            callback() if callback?
            return true
          else console.warn("Unrecognized stack ide ResponseUpdateSession: #{contents['tag']}")
        return false

  doCheckBuffer: (buffer, callback) =>
    console.debug("requesting checked buffer")
    rootDir = Util.getRootDir(buffer)
    @emitter.emit "backend-active"
    @updateSession buffer, () =>
      @emitter.emit "backend-active"
      @runStackIdeCmd rootDir, 'RequestGetSourceErrors', [],
        (contents) =>
          @emitter.emit "backend-idle"
          results = []
          for error in contents
            row = Number.parseInt(error['errorSpan']['contents']['spanFromLine'])
            col = Number.parseInt(error['errorSpan']['contents']['spanFromColumn'])
            path = error['errorSpan']['contents']['spanFilePath']
            uri = (try rootDir.getFile(rootDir.relativize(path)).getPath()) ? path
            msg = error['errorMsg']
            severity = switch error['errorKind'].substring(4).toLowerCase()
              when 'warning' then 'warning'
              when 'error' then 'error'
              else
                Util.debug "Unrecognized errorKind #{error['errorKind']}"
                'error'
            results.push
              uri: uri
              position: new Point(row - 1, col - 1)
              message: msg
              severity: severity
          callback results if callback?
          return true

  doLintBuffer: (buffer, callback) =>
