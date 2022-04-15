pragma solidity ^0.8.0;
//SPDX-License-Identifier: MIT

/// @notice ERC20 token contract interface
interface IERC20 {
    function transfer(address user, uint256 amount) external returns (bool);
}

interface IToken {
    function governor() external view returns (address);
}

contract XVMCtreasury {
  /// @notice Owner address
  address public owner;
  address public immutable token; // XVMC token(address)

  /// @notice Event emitted when new transaction is executed
  event ExecuteTransaction(address indexed token, address indexed recipientAddress, uint256 value);

  event ChangeOwner(address newOwner, uint256 time);

  constructor(address _XVMC) {
   token = _XVMC;
  }

  /// @notice Modifier to make a function callable only by the owner.
  modifier onlyOwner {
    require(msg.sender == owner, 'Only owner');
    _;
  }


  /**
   * Initiate withdrawal from treasury wallet
   */
  function requestWithdraw(address _token, address _receiver, uint _value) external onlyOwner {
    // If token address is 0x0, transfer native tokens
    if (_token == address(0) || _token == 0x0000000000000000000000000000000000001010) payable(_receiver).transfer(_value);
    // Otherwise, transfer ERC20 tokens
    else IERC20(_token).transfer(_receiver, _value);

    emit ExecuteTransaction(_token, _receiver, _value);
  }


  /**
   * Updates to the governor address(owner of masterchef(who owns the token))
   */
  function changeGovernor() external {
    owner = IToken(token).governor();

	emit ChangeOwner(owner, block.number);
  }

  /// @notice Fallback functions to receive native tokens
  receive() external payable { } 
  fallback() external payable { }
}
