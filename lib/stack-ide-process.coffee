{BufferedProcess, Range, Point, Emitter, CompositeDisposable} = require 'atom'
Util = require './util'
{extname} = require('path')
CP = require('child_process')

module.exports =
class StackIdeProcess
  backend: null
  processMap: null
  handlers: null

  constructor: ->
    @processMap = new Map
    @disposables = new CompositeDisposable
    @disposables.add @emitter = new Emitter

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
    proc = CP.spawn(stackPath, ['ide'], options)
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
    #TODO: handle malformed json
    Util.debug "Handling response: #{data}"
    if data? and data isnt ""
      try
        json = JSON.parse data
        tag = json["tag"]
        contents = json["contents"]
        switch tag
          when "ResponseWelcome" then @_handleResponseWelcome(contents)
          when "ResponseUpdateSession" then @_handleResponseUpdateSession(rootDir, contents)
          when "ResponseGetSourceErrors" then @_handleResponseGetSourceErrors(rootDir, contents)
          else console.warn "Unrecognized stack ide tag #{tag}: #{JSON.stringify(contents)}"
      catch error
        console.error("error parsing stack ide response: #{error}")

  _handleResponseWelcome: (contents) =>
    console.debug("Stack IDE started")
    @emitter.emit "backend-idle"

  _handleResponseUpdateSession: (rootDir, contents) =>
      switch contents['tag']
          when "UpdateStatusProgress" then =>
              @emitter.emit "backend-active"
          when "UpdateStatusDone"
            console.debug("finished updating")
            @emitter.emit "backend-idle"
            proc = @processMap.get(rootDir.getPath())
            if proc?
              cb = proc['callbackQueues']['ResponseUpdateSession'].pop()
              cb() if cb?
          else console.warn("Unrecognized stack ide ResponseUpdateSession: #{contents['tag']}")

  _handleResponseGetSourceErrors: (rootDir, contents) =>
      @emitter.emit "backend-idle"
      proc = @processMap.get(rootDir.getPath())
      if proc?
        cb = proc['callbackQueues']['ResponseGetSourceErrors'].pop()
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
            else ->
              Util.debug "Unrecognized errorKind #{error['errorKind']}"
              'error'

          results.push
            uri: uri
            position: new Point(row - 1, col - 1)
            message: msg
            severity: severity
        cb results if cb?

  runStackIdeCmd: (dir, command, contents, callbacks) =>
    contents = [] unless contents?
    cmd = JSON.stringify({tag: command, contents: contents })
    Util.debug "Trying to run stack-ide command in #{dir.getPath()}: #{cmd}"
    process = @spawnProcess(dir, @options)
    unless process
      Util.debug "Failed"
      return
    queues = @processMap.get(dir.getPath())['callbackQueues']
    for cbtype, cb of callbacks
      unless queues[cbtype]?
        queues[cbtype] = []
      if cb?
        queues[cbtype].unshift(cb)
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
    # crange = Util.toRange crange
    #
    # @queueCmd 'typeinfo',
    #   interactive: true
    #   dir: Util.getRootDir(buffer)
    #   options: Util.getProcessOptions(Util.getRootDir(buffer).getPath())
    #   command: 'type',
    #   uri: buffer.getUri()
    #   text: buffer.getText() if buffer.isModified()
    #   args: ["", crange.start.row + 1, crange.start.column + 1]
    #   callback: (lines) ->
    #     [range, type] = lines.reduce ((acc, line) ->
    #       return acc if acc != ''
    #       tokens = line.split '"'
    #       pos = tokens[0].trim().split(' ').map (i) -> i - 1
    #       type = tokens[1]
    #       myrange = new Range [pos[0], pos[1]], [pos[2], pos[3]]
    #       return acc unless myrange.containsRange(crange)
    #       return [myrange, type]),
    #       ''
    #     type = undefined unless type
    #     range = crange unless range
    #     callback {range, type}

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

  getLoadedModules: (buffer) =>
    dir = Util.getRootDir(buffer)
    @runStackIdeCmd dir, 'RequestGetLoadedModules', []

  updateSession: (buffer, callback) =>
    console.debug("requesting updated session")
    dir = Util.getRootDir(buffer)
    @runStackIdeCmd dir, 'RequestUpdateSession',
      [{"tag": "RequestSessionUpdate", "contents": []}],
      { 'ResponseUpdateSession': callback }


  doCheckBuffer: (buffer, callback) =>
    console.debug("requesting checked buffer")
    dir = Util.getRootDir(buffer)
    @updateSession buffer, () =>
      @runStackIdeCmd dir, 'RequestGetSourceErrors', [],
        { 'ResponseGetSourceErrors': callback }

  doLintBuffer: (buffer, callback) =>
    console.debug("requesting linting")
    @doCheckBuffer buffer, callback
