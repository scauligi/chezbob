/// <reference path="../typings/tsd.d.ts"/>

var git = require('git-rev-2');
import async = require('async');
var pkginfo = require('pkginfo')(module);
var http = require('http');
var repl = require('repl');
var stream = require('stream');
var util = require('util');
var bunyan = require('bunyan');
var serialport = require('serialport').SerialPort;
var jayson = require('jayson');
import Buffer = require('buffer');

var log;

class InitData {
    version: String;
    longVersion: String;

    mdbport: String;
    timeout: Number;
    remote_endpoint: String;
    rpc_port: number;

    loadVersion (initdata: InitData, callback: () => void) : void
    {
        log.debug("Getting version information...");
        initdata.version = module.exports.version;
        initdata.longVersion = module.exports.version;
        //if we are in a git checkout, append the short SHA.
        git.short(__dirname, function (initdata: InitData) {
            return function (err, str)
            {
                if (err === null)
                {
                    log.debug("Git checkout detected.");
                    initdata.version += "+";
                    initdata.longVersion += "/" + str;
                }
                log.info("mdb_server version " + initdata.longVersion);
                callback();
            }
        }(initdata))
    }

    prepareLogs = (initdata: InitData, callback: () => void) : void =>
    {
        log = bunyan.createLogger(
                {
                    name: 'mdb-server',
                    streams: [
                    {
                        stream: process.stdout,
                        level: "debug"
                    }
                    ]
                }
                );
        log.level("debug");
        log.info("Logging system initialized");
        callback();
    }

    init = (initdata : InitData, callback: (err,res) => void) : void =>
    {
        async.series([
                    function (cb) {initdata.prepareLogs(initdata, cb)},
                    function (cb) {initdata.loadVersion(initdata, cb)},
                    function (err, res)
                    {
                        callback(null, initdata);
                    }
                ]);
    }

    constructor() {
        this.mdbport = "/dev/mdb";
        this.timeout = 1000;
        this.remote_endpoint = "http://127.0.0.1:8080/api";
        this.rpc_port = 8081;
    }
}

class mdb_server {
    initdata : InitData; //initialization data

    solicit: boolean; //whether or not current_buffer was solicited
    solicit_cb; //callback for a solicitation
    solicit_tm; //timer for solicitation timeout
    last_buffer;
    current_buffer; //current data being read in
    port; // open port
    rpc_client;

    //sends the commands to reset the mdb device
    reset (mdb : mdb_server) {
        async.series([
                // Reset the coin changer
                function (cb) { mdb.sendread("R1", cb); },
                function (cb) { mdb.sendread("N FFFF", cb); },
                function (cb) { mdb.sendread("E1", cb); },
                // Reset the bill reader
                function (cb) { mdb.sendread("R1", cb); },
                function (cb) { mdb.sendread("P2", cb); },
                function (cb) { mdb.sendread("L FFFF", cb); },
                function (cb) { mdb.sendread("V 0000", cb); },
                function (cb) { mdb.sendread("J FFFF", cb); },
                function (cb) { mdb.sendread("E2", cb); }
                ],
                function (error, result)
                {
                    if (error !== null)
                    {
                        log.info("Coin reader and bill reader successfully reset.", result);
                    }
                }
                );
    }

    //asynchronusly sends a string and returns the result in a callback
    //a timeout occurs if data is not returned within the timeout.
    sendread = (data: String, cb) =>
    {
        if (this.solicit)
        {
            //already someone waiting, fail
            log.warn("Sendread failed, request in progress");
            cb("Request in progress, please try again!", null);
        }
        else
        {
            this.solicit = true;
            this.solicit_cb = cb;
            this.solicit_tm = setTimeout(function(mdb:mdb_server){return function() {
                log.error("sendread request failed, timeout!");
                mdb.solicit_cb = null;
                mdb.solicit_tm = null;
                mdb.solicit = false;
                cb("Request timed out!", null);
            }}(this), this.initdata.timeout);


            this.send(data, null);
        }
    }

    //asynchrnously sends a string over port
    send = (data: String, cb) => {
        log.debug("send: ", data);
        this.port.write(data + '\r', function(error)
                {
                    if (typeof error !== 'undefined' && error && error !== null)
                    {
                        log.error("Couldn't write to serial port, " + error);
                    }
                    if (typeof cb !== 'undefined' && cb)
                    {
                        cb(error);
                    }
                })
    }

    start = () => {
        log.info("mdb_server starting, listening on " + this.initdata.mdbport);
        this.port = new serialport(this.initdata.mdbport);
        this.port.on("open", function(mdb: mdb_server){ return function ()
                {
                    log.debug("serial port successfully opened.");
                    mdb.port.on('data', function(data : Buffer)
                        {
                            //it is highly unlikely that we got more than
                            //1 byte, but if we did, make sure to process
                            //each byte
                            var process_last : boolean = false;
                            for (var i : number = 0; i < data.length; i++)
                            {
                                switch (data[i])
                                {
                                    case 0xa:
                                        log.debug("received ACK");
                                    break;
                                    case 0xd:
                                        mdb.last_buffer = mdb.current_buffer;
                                        mdb.current_buffer = "";
                                        log.debug("received " + mdb.last_buffer);
                                        //mark that we need to send the last buffer
                                        process_last = true;
                                        break;
                                    default:
                                        mdb.current_buffer += data.toString('utf8', i, i+1);
                                }
                            }
                            if (process_last)
                            {
                                //if this is a solicited request, clear the timer and
                                //call the callback
                                if (mdb.solicit)
                                {
                                    var cb_temp = mdb.solicit_cb;
                                    mdb.solicit_cb = null;
                                    mdb.solicit = false;
                                    clearTimeout(mdb.solicit_tm);
                                    cb_temp(null, mdb.last_buffer);
                                }
                                else
                                {
                                    //otherwise send to the remote endpoint.
                                    mdb.rpc_client.request("Soda.remotemdb", data, function (err, response)
                                            {
                                                if (err)
                                                {
                                                    log.error("Error contacting remote endpoint", err);
                                                }
                                                else
                                                {
                                                    log.debug("remotemdb successful, response=", response);
                                                }
                                            });
                                }
                            }
                        });
                    mdb.reset(mdb);
                    var server = jayson.server(
                            {
                                "Mdb.command": function(mdb : mdb_server) { return function (command: String, callback)
                                {
                                    log.debug("remote request: " + command);
                                    mdb.sendread(command, function(err, result)
                                        {
                                            callback(err, result);
                                        });
                                }}(mdb)
                            }
                            )
                    server.http().listen(mdb.initdata.rpc_port);
                    log.info("rpc endpoint listening on port " + mdb.initdata.rpc_port);
                }}(this));
        this.port.on("error", function (error)
                {
                    log.error("Fatal serial port error - " + error);
                    process.exit(1);
                });
    }

    constructor(initdata : InitData) {
        this.initdata = initdata;
        this.current_buffer = "";
        this.solicit_cb = null;
        this.rpc_client = jayson.client.http(initdata.remote_endpoint);
    }
}
export class App {
    private initdata : InitData;

    main(args: Object[])
    {
        this.initdata = new InitData();
        this.initdata.init(this.initdata,
                function (err, res: InitData)
                {
                    var mdb = new mdb_server(res);
                    mdb.start();
                }
                );
    }

    constructor () {}
}
