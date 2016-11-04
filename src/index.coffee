Promise = require 'promise'
keygen = require 'keygen'
aws = require 'aws-sdk'

id_for = (it) ->
  it?.identifier ? it

class Model

  constructor: (@name) ->
    @doc_client = new aws.DynamoDB.DocumentClient()

  _request: (method, params, include_table=true) ->
    params ?= {}
    params.TableName = @name if include_table
    self = @
    new Promise (resolve, reject) ->
      self.doc_client[method] params, (err, result) ->
        if err?
          console.log "DynamoDB Error: #{err}"
          return reject(err)
        resolve result

  put: (item, condition) ->
    params = Item: item
    if condition?
      params.ConditionExpression = condition.expression
      params.ExpressionAttributeNames = condition.names
      params.ExpressionAttributeValues = condition.values
    @_request('put', params).then (result) ->
      Promise.resolve item

  put_all: (items) ->
    params = RequestItems: {}
    params.RequestItems[@name] = (PutRequest: Item: item for item in items)
    self = @
    @_request('batchWrite', params, false).then (results) ->
      Promise.resolve items

  insert: (item) ->
    item.identifier = keygen.url @key_size unless item.identifier?
    @put item, expression: 'identifier <> :id', values: ':id': item.identifier

  update: (key, update) ->
    params = Key: key, UpdateExpression: update.expression
    params.ExpressionAttributeNames = update.names
    params.ExpressionAttributeValues = update.values
    @_request('update', params).then (result) ->
      Promise.resolve result.Items

  get: (thing, params={}) ->
    params.Key = @key_for thing
    @_request('get', params).then (result) ->
      Promise.resolve result.Item

  delete: (thing, params={}) ->
    params = Key: @key_for thing
    @_request('delete', params).then (result) ->
      Promise.resolve result.Item

  query: (params) ->
    self = @
    params.KeyConditionExpression ?= params.expression
    params.ExpressionAttributeNames ?= params.names
    params.ExpressionAttributeValues ?= params.values
    @_request('query', params).then (result) ->
      Promise.resolve result.Items

  scan: (params={}) ->
    self = @
    params.FilterExpression ?= params.expression
    params.ExpressionAttributeNames ?= params.names
    params.ExpressionAttributeValues ?= params.values
    @_request('scan', params).then (result) ->
      Promise.resolve result.Items

  for_keys: (keys) ->
    params = RequestItems: {}
    params.RequestItems[@name] = Keys: keys
    self = @
    @_request('batchGet', params, false).then (results) ->
      Promise.resolve results.Responses[self.name]

  for_id: (id) ->
    @get identifier: id

  for_ids: (ids) ->
    @for_keys (identifier: id for id in ids)

  key_for: (item) ->
    key = {}
    key[@hash_key] = item[@hash_key]
    key[@range_key] = item[@range_key] if @range_key?
    key

  hash_key: 'identifier'

  range_key: undefined

  id_for: id_for

  @model: (name) ->
    new @ name

  @extend: (module, name, extension={}) ->
    Type = class extends @
    Type::[prop] = value for prop, value of extension
    model = new Type name
    module.exports = model

  @update_builder: (item) ->
    set_exp = 'set '
    names = {}
    values = {}
    parts = []
    for name, value of item
      parts.push "##{name} = :#{name}"
      names["##{name}"] = name
      values[":#{name}"] = value
    {expression: "#{set_exp} #{parts.join(', ')}", names, values}

  @id_for: id_for

# Model::[name] = proxy name for name in ['scan']

module.exports = Model