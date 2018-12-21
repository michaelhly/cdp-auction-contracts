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
    const auctionInstance = new web3.eth.Contract(
      Auction.abi,
      Auction.networks["42"].address
    );

    const auctionLog = auctionInstance.getPastEvents(
      "LogAuctionEntry",
      { fromBlock: 0, toBlock: "latest" },
      (errors, events) => {
        if (!errors) {
          console.log(events);
        }
      }
    );
  };

  constructor() {
    super();
    this.fetchAuctions();
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
