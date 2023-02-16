// SPDX-License-Identifier: NONE
pragma solidity 0.8.0;
interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
}

interface IChainlink {
  function latestAnswer() external view returns (int256);
}

interface IGovernor {
    function currentVaultAllocation() external view returns (uint256);
    function setPool(uint256 _pid, uint256 _allocPoint, uint16 _depositFeeBP, bool _withUpdate) external;
    function maticVault() external view returns (address);
    function usdcVault() external view returns (address);
    function wethVault() external view returns (address);
}

interface IToken {
    function governor() external view returns (address);
}

contract VaultRebalancer {
    address public immutable xvmc = 0x970ccEe657Dd831e9C37511Aa3eb5302C1Eb5EEe;
    address public immutable wETH = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
  address public immutable usdc = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;

    address public chainlinkWETH = 0xF9680D99D6C9589e2a93a78A04A279e509205945;
  address public chainlinkMATIC = 0xAB594600376Ec9fD91F8e885dADF0CE036862dE0;

    //rebalances pools accordingly
    function rebalanceVaults() external {
        IGovernor governor = IGovernor(IToken(xvmc).governor());

        uint256 currentVaultAllocation = governor.currentVaultAllocation();
        uint256 maticPrice = uint256(IChainlink(chainlinkMATIC).latestAnswer());
    uint256 wETHprice = uint256(IChainlink(chainlinkWETH).latestAnswer());

        uint256 usdcValue = IERC20(usdc).balanceOf(governor.usdcVault()) * 1e12;
        uint256 maticValue = (governor.maticVault()).balance * maticPrice / 1e8;
        uint256 wethValue = IERC20(wETH).balanceOf(governor.wethVault()) * wETHprice / 1e8;

        uint256 total = usdcValue + maticValue + wethValue;

        governor.setPool(11, (10000 * maticValue / total * currentVaultAllocation / 10000), 0, false);
        governor.setPool(12, (10000 * usdcValue / total * currentVaultAllocation / 10000), 0, false);
        governor.setPool(13, (10000 * wethValue / total * currentVaultAllocation / 10000), 0, false);
    }
}
