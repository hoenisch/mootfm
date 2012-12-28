should = require 'should'
async = require "async"
io = require 'socket.io-client'

Statement = require "../models/statement"
http = require "request"
User = require "../models/user"
DatabaseHelper = require "../models/db-helper"

# To avoid annoying logging during tests
logfile = require('fs').createWriteStream 'extravagant-zombie.log'

url = "http://localhost:8081"
user_data=
  name: "Test User"
  email: "test@user.at"
  password: "password"
  username: "test@user.at"

testState=
  title:"Apple sucks"

testState2=
  title:"Apple lags behind"
  side: "pro"


url = "http://localhost:8081"
options =
  transports: ['websockets']
  'force new connection':true

create_user = (callback)->
  User.get_by_username user_data.email , (err, user) ->
    if (err)
      User.create user_data, callback
    else
      callback()

login = (callback)->
  http
    method: "Post"
    url: url + "/login"
    followRedirect:false
    form: 
      username: user_data.email
      password: user_data.password
  , (err, res, body) ->
    return done err if err
    res.headers.location.should.be.equal "/loggedin", "wrong redirect, probably because of failed login"
    res.statusCode.should.be.equal 302
    http
      method: "GET"
      url: url + "/statement"
    , (err, res, body) ->
      console.log "got here"
      res.body.search(user_data.email).should.not.be.equal -1
      console.log "got here2"
      options.query= res.request.headers.cookie
      callback()

describe "Socket IO", ->
  beforeEach (done) ->
    require('../server').start (err)->
      create_user ->
        login done

  it "post should be successful.", (done) ->
    client1 = io.connect(url, options)
    client1.emit "post",testState
    client1.once "statement", (statements) ->
      statements[0].title.should.equal(testState.title,"should receive same statement title on create");
      #state.should.have.property('user')
      #state.user.should.have.property('id')
      #state.user.should.have.property('name')
      #state.user.should.have.property('picture_url')
      client1.disconnect()
      done()
  it "get should be successful.", (done) ->
    client1 = io.connect(url, options)
    client1.emit "post",testState
    client1.once "statement", (statements) ->
      client1.emit "get",statements[0].id
      client1.once "statement", (statements) ->
        statements.should.be.an.instanceOf(Array)
        statements.length.should.be.equal 1, "wrong number of statements found"
        statements[0].title.should.equal testState.title,"should receive same statement title on create"
        #state.should.have.property('user')
        #state.user.should.have.property('id')
        #state.user.should.have.property('name')
        #state.user.should.have.property('picture_url')
        client1.disconnect()
        done()
  it "argue should be successful.", (done) ->
    ids= []
    client1 = io.connect(url, options)
    client1.emit "post",testState
    client1.once "statement", (statements) ->
      ids[0]=statements[0].id
      testState2.parent= statements[0].id
      client1.emit "post",testState2
      client1.once "statement", (statements) ->
        statements[0].parent.should.ne.equal testState2.parent, "wrong parent found"
        statements[0].side.should.ne.equal testState2.side, "wrong side found"
        statements[0].vote.should.ne.equal 0, "wrong vote found"
        ids[1]=statements[0].id
        client1.emit "get",ids[0]
        client1.once "statement", (statements) ->
          statements.should.be.an.instanceOf(Array)
          statements.length.should.be.equal 2, "wrong number of statements found"
          
          #state.should.have.property('user')
          #state.user.should.have.property('id')
          #state.user.should.have.property('name')
          #state.user.should.have.property('picture_url')
          client1.disconnect()
          done()

  it "vote should be successful.", (done) ->
    ids= []
    client1 = io.connect(url, options)
    client1.emit "post",testState
    client1.once "statement", (statements) ->
      ids[0]=statements[0].id
      testState2.parent= statements[0].id
      client1.emit "post",testState2
      client1.once "statement", (statements) ->
        ids[1]=statements[0].id
        client1.emit "get",ids[0]
        client1.once "statement", (statements) ->
          statements.should.be.an.instanceOf(Array)
          statements.length.should.be.equal 2, "wrong number of statements found"
          for stmt in statements
            if stmt.id==ids[1]
              point=stmt
              stmt.side.should.be.equal testState2.side, "wrong side found for point"
              stmt.vote.should.be.equal 0, "wrong number of votes for point"
          client1.emit "vote",point,1
          client1.once "statement", (statements) ->
            statements.should.be.an.instanceOf(Array)
            statements.length.should.be.equal 1, "wrong number of statements found"
            statements[0].vote.should.be.equal 1, "wrong number of votes for point"
            #state.should.have.property('user')
            #state.user.should.have.property('id')
            #state.user.should.have.property('name')
            #state.user.should.have.property('picture_url')
            client1.disconnect()
            done()
