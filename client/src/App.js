import React, { Component } from "react";
import logo from "./logo.svg";
import "./App.css";

import Web3 from "web3";
const web3 = new Web3(new Web3(window.web3.currentProvider));

const Auction = require("./artifacts/Auction");

class App extends Component {
  state = {
    auctions: [],
    tokens: []
  };

  fetchAuctions = () => {
    let auctions = [];

    const auctionInstance = new web3.eth.Contract(
      Auction.abi,
      Auction.networks["42"].address
    );

    auctionInstance.getPastEvents(
      "LogAuctionEntry",
      { fromBlock: 0, toBlock: "latest" },
      (errors, events) => {
        if (!errors) {
          for (var i = 0; i < events.length; i++) {
            let auction = {
              key: events[i].returnValues["auctionId"],
              ask: events[i].returnValues["ask"],
              cdp: events[i].returnValues["cdp"],
              expiry: events[i].returnValues["expiry"],
              seller: events[i].returnValues["seller"],
              token: events[i].returnValues["token"]
            };
            auctions.push(auction);
          }
        }
      }
    );
    return auctions;
  };

  constructor() {
    super();
    const auctions = this.fetchAuctions();
    this.state = { auctions: auctions };
  }

  render() {
    return (
      <div className="App">
        <header className="App-header">
          <img src={logo} className="App-logo" alt="logo" />
          <p>
            Edit <code>src/App.js</code> and save to reload.
          </p>
          <a
            className="App-link"
            href="https://reactjs.org"
            target="_blank"
            rel="noopener noreferrer"
          >
            Learn React
          </a>
        </header>
      </div>
    );
  }
}

export default App;
