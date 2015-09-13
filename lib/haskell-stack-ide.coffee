StackIdeProcess = require './stack-ide-process'
IdeBackend = require './ide-backend'
CompletionBackend = require './completion-backend'

module.exports = HaskellStackIde =
  process: null

  config:
    stackPath:
      type: 'string'
      default: 'stack'
      description: 'Path to stack'
    debug:
      type: 'boolean'
      default: false
    
  activate: (state) ->
    @process = new StackIdeProcess

  deactivate: ->
    @process?.destroy()
    @process = null
    @ideBackend = null
    @completionBackend = null

  provideIdeBackend: ->
    @ideBackend ?= new IdeBackend @process
    @ideBackend

  provideCompletionBackend: ->
    @completionBackend ?= new CompletionBackend @process
    @completionBackend

  provideLinter: ->
    return
    # if atom.packages.getLoadedPackage('ide-haskell')
      # return unless atom.config.get 'ide-haskell.useLinter'
    # backend = HaskellGhcMod.provideIdeBackend()
    # [
    #   func: 'checkBuffer'
    #   lintOnFly: false
    #   scopes: ['source.haskell', 'text.tex.latex.haskell']
    # ,
    #   func: 'lintBuffer'
    #   lintOnFly: true
    #   scopes: ['source.haskell']
    # ].map ({func, scopes, lintOnFly}) ->
    #   grammarScopes: scopes
    #   scope: 'file'
    #   lintOnFly: lintOnFly
    #   lint: (textEditor) ->
    #     return new Promise (resolve, reject) ->
    #       backend[func] textEditor.getBuffer(), (res) ->
    #         resolve res.map ({uri, position, message, severity}) ->
    #           [message, messages...] = message.split /^(?!\s)/gm
    #           {
    #             type: severity
    #             text: message
    #             multiline: true
    #             filePath: uri
    #             range: [position, position.translate [0, 1]]
    #             trace: messages.map (text) ->
    #               type: 'trace'
    #               text: text
    #               multiline: true
    #           }
