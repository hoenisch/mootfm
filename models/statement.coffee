# all we'll really store is the node; the rest of our properties will be
# derivable or just pass-through properties (see below).
Statement = module.exports = Statement = (@_node) ->

neo4j = require "neo4j"
async = require "async"

db = new neo4j.GraphDatabase(process.env.NEO4J_URL or "http://localhost:7474")

INDEX_NAME = "nodes"
INDEX_KEY = "type"
INDEX_VAL = "statements"

proxyProperty = (prop, isData) ->
  Object.defineProperty Statement::, prop,
    get: ->
      if isData
        @_node.data[prop]
      else
        @_node[prop]

    set: (value) ->
      if isData
        @_node.data[prop] = value
      else
        @_node[prop] = value

# constants:
proxyProperty "id"
proxyProperty "exists"
proxyProperty "title", true
proxyProperty "type", true

Statement::_getFollowingRel = (other, callback) ->
  query = "
    START statement=node(#{@id}), other=node(#{other.id})
    MATCH (statement) -[rel]-> (other)
    RETURN rel
  "
  db.query query,(err, results) ->
    return callback(err) if err
    console.log "get rel", results
    rel = results[0] and results[0]["rel"]
    callback null, rel

Statement::save = (callback) ->
  @_node.save callback

Statement::del = (callback) ->
  @_node.del callback, true # true = yes, force it (delete all relationships)

Statement::get_or_create_vote_point = (side,callback) ->
  #get existing votepoint
  query ="
    START statement=node(#{@id}), votepoint=node:#{INDEX_NAME}(#{INDEX_KEY}=\"#{INDEX_VAL}\")
    MATCH votepoint --> statement
    WHERE has(votepoint.side) and votepoint.side = \"#{side}\"
    RETURN votepoint
    "
  db.query query, (err, results) =>
    return callback(err) if err
    if results.length>1
      return callback "DB inconsistent: Too many matching votepoints found in db"
    if results.length==1
      return callback null, results[0]["votepoint"]
    else
      votepoint = db.createNode({"type":"votepoint","side":side})
      votepoint.save (err) =>
        return callback(err)  if err
        votepoint.index INDEX_NAME, INDEX_KEY, INDEX_VAL, (err) =>
          return callback(err)  if err
          votepoint.createRelationshipTo @_node, "", {}, (err)->
            return callback(err)  if err
            callback null, votepoint

Statement::argue = (other, side, callback) ->
  other.get_or_create_vote_point side,(err,votepoint)=>
    return callback(err) if err
    @_node.createRelationshipTo votepoint, "", {}, callback

Statement::unargue = (other, side, callback) ->
  other.get_or_create_vote_point side,(err,votepoint)=>
    return callback(err)  if err
    @_getFollowingRel votepoint, (err, rel) ->
      return callback(err)  if err
      console.log "REL",rel
      return callback(null)  unless rel
      console.log "deleting rel"
      rel["delete"] (err)->
        console.log "ERR",err
        callback(err)

Statement::vote = (point, side, vote, callback) ->
  total_votes=1
  callback null, total_votes
  #@_node.createRelationshipTo other._node, side, {}, callback

Statement::getArguments = (callback) ->
  query ="
    START statement=node(#{@id}), arguments=node:#{INDEX_NAME}(#{INDEX_KEY}=\"#{INDEX_VAL}\")
    MATCH arguments --> votepoint --> statement
    RETURN arguments, votepoint.side
    "
    #WHERE votepoint.type = \"votepoint\" and arguments.type = \"point\"
  db.query query, (err, results) ->
    return callback(err)  if err
    sides = {}
    i = 0
    side_list = (result["votepoint.side"] for result in results)
    for side in side_list when side
      sides[side]=[]
    for result in results
      sides[result["votepoint.side"]].push new Statement(result["arguments"])
    callback null, sides

# static methods:

Statement.get = (id, callback) ->
  db.getNodeById id, (err, node) ->
    return callback(err)  if err
    callback null, new Statement(node)

# creates the statement and persists (saves) it to the db, incl. indexing it:
Statement.create = (data, callback) ->
  data["type"]="point"
  node = db.createNode(data)
  statement = new Statement(node)
  node.save (err) ->
    return callback(err)  if err
    node.index INDEX_NAME, INDEX_KEY, INDEX_VAL, (err) ->
      return callback(err)  if err
      callback null, statement

# creates a json compatible representation of this statement
Statement::get_representation = (level, callback) ->
  representation=
    title:@title
    id:@id
  return callback null, representation if level <= 0
  @getArguments (err, argument_dict) =>
    return callback(err) if err
    sides={}
    async.forEach ([side,stmt_arguments] for side, stmt_arguments of argument_dict), ([side,stmt_arguments],callback)->
      async.map stmt_arguments, (argument,callback)->
        argument.get_representation level-1, callback
      , (err, side_arguments) ->
        return callback(err) if err
        sides[side]=side_arguments
        callback null
    , (err) ->
      return callback(err) if err
      representation["sides"]=sides
      callback null, representation

