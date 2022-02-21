pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "./DividendTracker1.sol";
import "./DividendTracker2.sol";

contract TINA is Context, ERC20, ERC20Burnable , Ownable {
    using SafeMath for uint256;
    using Address for address;
    
    bool private swapping;
    
    DividendTrackerBNB public dividendTracker; // For BNB
    DividendTracker1 public dividendTrackerBETH; // For BETH
    DividendTracker1 public dividendTrackerBTCB; // For BTCB
    
    address public marketingAddress;
    address public devAddress;
    address public burnAddress = 0x000000000000000000000000000000000000dEaD;
    
    IUniswapV2Router02 public immutable uniswapV2Router;
    address public immutable uniswapV2Pair;
    address public immutable uniswapV2PairBTCB;
    address public immutable uniswapV2PairBETH;
    
    address public BTCB ;
    address public BETH ;
    
    uint256 public liquidityTax = 30;
    uint256 public dividendTax = 40;
    uint256 public marketingTax = 20;
    uint256 public devTax = 0;
    uint256 public burnTax = 10;
    
    uint256 public BTCBdivisor = 50;
    uint256 public BETHdivisor = 40;
    uint256 public BNBdivisor = 10;
    
    uint256 private forLiquidity;
    uint256 private forDividends;
    uint256 private forBTCB;
    uint256 private forBETH;
    uint256 private forBNB;
    uint256 private flag;
    
    uint256 public maxTxAmount;
    uint256 public maxBalance;
    
    mapping (address => bool) public _isExcludedFromFee;
    
     constructor (IUniswapV2Router02 _router, address _beth, address _btcb) ERC20("TINA Token","TINA") {
        
        BTCB = _btcb;
        BETH = _beth;
        
        dividendTracker = new DividendTrackerBNB(); // BNB
        dividendTrackerBETH = new DividendTracker1(); // BETH
        dividendTrackerBTCB = new DividendTracker1(); // BTC
        
        _mint(msg.sender, totalSupply());
        maxTxAmount = totalSupply().mul(5).div(1000);
        maxBalance = totalSupply().mul(10).div(1000);
        
        uniswapV2Router = _router;
        
        uniswapV2Pair = IUniswapV2Factory(_router.factory()) // token and BNB
            .createPair(address(this), _router.WETH());

        uniswapV2PairBTCB = IUniswapV2Factory(_router.factory()) // token and _routerBTCB
            .createPair(address(this), BTCB);
        
        uniswapV2PairBETH = IUniswapV2Factory(_router.factory())  // token and  _routerBETH
            .createPair(address(this), BETH);
            
            
        dividendTrackerBETH.switchRewardTokenAddress(_beth);
        dividendTrackerBTCB.switchRewardTokenAddress(_btcb);
        
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;
        
    }
    
    function decimals() public view virtual override returns (uint8) {
        return 7;
    }
    
    function totalSupply() public view virtual override returns (uint256) {
        return 100000000 * 10 ** decimals();
    }
    
    function getTransferAmounts(uint256 _amount) private returns (uint256, uint256) {
        uint256 liquidityTaxAmount = _amount.mul(liquidityTax).div(1000);
        uint256 dividendTaxAmount = _amount.mul(dividendTax).div(1000)
        forLiquidity = forLiquidity.add(liquidityTaxAmount);
        forDividends = forDividends.add(dividendTaxAmount);
        forBTCB = forBTCB.add(forDividends.mul(BTCBdivisor).div(100));
        forBETH = forBETH.add(forDividends.mul(BETHdivisor).div(100));
        forBNB = forBNB.add(forDividends.mul(BNBdivisor).div(100));
        return (_amount.sub(liquidityTaxAmount.add(dividendTaxAmount)),liquidityTaxAmount.add(dividendTaxAmount));
    }
    
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "TINA: transfer from the zero address");
        require(to != address(0), "TINA: transfer to the zero address");
        require(amount <= maxTxAmount,"TINA: transfer more than allowed amount");
        if (amount == 0) {
            super._transfer(from, to, 0);
            return;
        }
        
        uint256 contractTokenBalance = balanceOf(address(this));
        bool canSwap = contractTokenBalance >= maxTxAmount;
        
        if(canSwap &&
            !swapping &&
            from != owner() &&
            to != owner()
        ) {
            swapping = true;
            
            if(flag == 0){
                swapAndSendDividends(flag, forBTCB);
                flag = 1;
            } else if(flag == 1) {
                swapAndSendDividends(flag, forBETH);
                flag = 2;
            } else if(flag == 2) {
                swapAndSendDividends(flag, forBNB);
                flag = 0;
            }
            
            swapAndLiquify(forLiquidity);
            swapping = false;
        }
        
        bool takeFee = true;
        if (_isExcludedFromFee[from] || _isExcludedFromFee[to]) {
            takeFee = false;
        }
        
        if (takeFee) {
            (uint256 transferAmount, uint256 fees) = getTransferAmounts(amount);
            uint256 marketingAmount = amount.mul(marketingTax).div(1000);
            uint256 devAmount = amount.mul(devTax).div(1000);
            uint256 burnAmount = amount.mul(burnTax).div(1000);
            amount = transferAmount.sub(marketingAmount.add(devAmount).add(burnAmount));
            super._transfer(from, address(this), fees);
            super._transfer(from, marketingAddress, marketingAmount);
            super._transfer(from, devAddress, devAmount);
            super._transfer(from, burnAddress, burnAmount);
        }

        super._transfer(from, to, amount);
        
        require(balanceOf(to) <= maxBalance,"TINA: Balance exceed max balance");
        
    }
    
    function swapAndLiquify(uint256 tokens) private {
        // split the contract balance into halves
        uint256 half = tokens.div(2);
        uint256 otherHalf = tokens.sub(half);

        uint256 newBalance = swapTokenforBNB(half);

        // add liquidity to uniswap
        addLiquidity(otherHalf, newBalance);
        forLiquidity = 1;
    }
    
    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // add the liquidity
        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(0),
            block.timestamp
        ); 
    }
    
    function swapAndSendDividends(uint256 _flag, uint256 tokens) private {
        if(_flag == 0){
            swapTokenforBTCB(tokens);
            uint256 dividends = IERC20(BTCB).balanceOf(address(this));
            bool success = IERC20(BTCB).transfer(address(dividendTrackerBTCB) ,dividends);
            
             if (success) {
                 dividendTrackerBTCB.distributeRewardTokenDividends(dividends);
                 forDividends = forDividends.sub(tokens);
                 forBTCB = 1;
             }
        } else if(_flag == 1) {
            swapTokenforBETH(tokens);
            uint256 dividends = IERC20(BETH).balanceOf(address(this));
            bool success = IERC20(BETH).transfer(address(dividendTrackerBETH) ,dividends);
            
             if (success) {
                 dividendTrackerBETH.distributeRewardTokenDividends(dividends);
                 forDividends = forDividends.sub(tokens);
                 forBETH = 1;
             }
        } else if(_flag ==2) {
            uint256 dividends = swapTokenforBNB(tokens);
            (bool success,) = address(dividendTracker).call{value: dividends}(""); 
            
            if(success) {
                dividendTracker.distributeRewardTokenDividends(dividends);
                forDividends = forDividends.sub(tokens);
                forBNB = 1;
            }
        }
    }
    
    function swapTokenforBTCB(uint256 _amount) private {
        address[] memory path = new address[](3);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        path[2] = BTCB;

        _approve(address(this), address(uniswapV2Router), _amount);

        // make the swap
        uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _amount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }
    
    function swapTokenforBETH(uint256 _amount) private {
        address[] memory path = new address[](3);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        path[2] = BETH;

        _approve(address(this), address(uniswapV2Router), _amount);

        // make the swap
        uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _amount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }    
    
    function swapTokenforBNB(uint256 _amount) private returns(uint256) {
        address[] memory path = new address[](3);
        uint256[] memory amount = new uint256[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), _amount);

        // make the swap
        amount = uniswapV2Router.swapExactTokensForETH(
            _amount,
            0,
            path,
            address(this),
            block.timestamp
        );
        
        return amount[1];
    }
    
    
    
    // -------Exclude dividends ----------
    function excludeFromDividends(address account) external onlyOwner {
        dividendTracker.excludeFromDividends(account);
    }
    
    function excludeFromDividendsBETH(address account) external onlyOwner {
        dividendTrackerBETH.excludeFromDividends(account);
    }
    
    function excludeFromDividendsBTCB(address account) external onlyOwner {
        dividendTrackerBTCB.excludeFromDividends(account);
    }
    
    // -------- isExcludedFromDividends  ----------
    function isExcludedFromDividends(address account) external view returns (bool){
        return dividendTracker.excludedFromDividends(account);
    }
    
    function isExcludedFromDividendsBETH(address account) external view returns (bool){
        return dividendTrackerBETH.excludedFromDividends(account);
    }
    
    function isExcludedFromDividendsBTCB(address account) external view returns (bool){
        return dividendTrackerBTCB.excludedFromDividends(account);
    }
    
    // ------- updateDividendTracker ---------
    function updateDividendTrackerBNB(address newAddress) public onlyOwner {
        require(newAddress != address(dividendTracker), "Tina: The dividend tracker already has that address");

        DividendTrackerBNB newDividendTracker = DividendTrackerBNB(payable(newAddress));

        require(newDividendTracker.owner() == address(this), "Tina: The new dividend tracker must be owned by the HoneyPad token contract");

        newDividendTracker.excludeFromDividends(address(newDividendTracker));
        newDividendTracker.excludeFromDividends(address(this));
        newDividendTracker.excludeFromDividends(address(uniswapV2Router));

        dividendTracker = newDividendTracker;
    }
    
    function updateDividendTrackerBETH(address newAddress) public onlyOwner {
        require(newAddress != address(dividendTrackerBETH), "Tina: The dividend tracker already has that address");

        DividendTracker1 newDividendTracker = DividendTracker1(payable(newAddress));

        require(newDividendTracker.owner() == address(this), "Tina: The new dividend tracker must be owned by the HoneyPad token contract");

        newDividendTracker.excludeFromDividends(address(newDividendTracker));
        newDividendTracker.excludeFromDividends(address(this));
        newDividendTracker.excludeFromDividends(address(uniswapV2Router));

        dividendTrackerBETH = newDividendTracker;
    }
    
    function updateDividendTrackerBTCB(address newAddress) public onlyOwner {
        require(newAddress != address(dividendTrackerBTCB), "Tina: The dividend tracker already has that address");

        DividendTracker1 newDividendTracker = DividendTracker1(payable(newAddress));

        require(newDividendTracker.owner() == address(this), "Tina: The new dividend tracker must be owned by the HoneyPad token contract");

        newDividendTracker.excludeFromDividends(address(newDividendTracker));
        newDividendTracker.excludeFromDividends(address(this));
        newDividendTracker.excludeFromDividends(address(uniswapV2Router));
        
        dividendTrackerBTCB = newDividendTracker;
    }
    
    // -------- updateClaimWait ------------
    function updateClaimWait(uint256 claimWait) external onlyOwner {
        dividendTracker.updateClaimWait(claimWait);
    }
    
     function updateClaimWaitBETH(uint256 claimWait) external onlyOwner {
        dividendTrackerBETH.updateClaimWait(claimWait);
    }
    
     function updateClaimWaitBTCB(uint256 claimWait) external onlyOwner {
        dividendTrackerBTCB.updateClaimWait(claimWait);
    }


    
    // --------- updateMinimumTokenBalanceForDividends ------------
    function updateMinimumTokenBalanceForDividends(uint256 newTokenBalance) external onlyOwner {
        dividendTracker.updateMinimumTokenBalanceForDividends(newTokenBalance);
    }
    
    function updateMinimumTokenBalanceForDividendsBETH(uint256 newTokenBalance) external onlyOwner {
        dividendTrackerBETH.updateMinimumTokenBalanceForDividends(newTokenBalance);
    }
    
    function updateMinimumTokenBalanceForDividendsBTCB(uint256 newTokenBalance) external onlyOwner {
        dividendTrackerBTCB.updateMinimumTokenBalanceForDividends(newTokenBalance);
    }
    
    
    // ------- getClaimWait -----------------
    function getClaimWait() external view returns(uint256) {
        return dividendTracker.claimWait();
    }
    
    function getClaimWaitBETH() external view returns(uint256) {
        return dividendTrackerBETH.claimWait();
    }
    
    function getClaimWaitBTCB() external view returns(uint256) {
        return dividendTrackerBTCB.claimWait();
    }
    
    
    // ---------- getTotalDividendsDistributed ---------------
    function getTotalDividendsDistributed() external view returns (uint256) {
        return dividendTracker.totalDividendsDistributed();
    }
    
    function getTotalDividendsDistributedBETH() external view returns (uint256) {
        return dividendTrackerBETH.totalDividendsDistributed();
    }
    
    function getTotalDividendsDistributedBTCB() external view returns (uint256) {
        return dividendTrackerBTCB.totalDividendsDistributed();
    }
    
    
    // ------------- withdrawableDividendOf ---------------
    function withdrawableDividendOf(address account) public view returns(uint256) {
        return dividendTracker.withdrawableDividendOf(account);
    }
    
    function withdrawableDividendOfBETH(address account) public view returns(uint256) {
        return dividendTrackerBETH.withdrawableDividendOf(account);
    }
    
    function withdrawableDividendOfBTCB(address account) public view returns(uint256) {
        return dividendTrackerBTCB.withdrawableDividendOf(account);
    }
    
    
    /// ------------- dividendTokenBalanceOf -----------------
    function dividendTokenBalanceOf(address account) public view returns (uint256) {
        return dividendTracker.balanceOf(account);
    }
    
    function dividendTokenBalanceOfBETH(address account) public view returns (uint256) {
        return dividendTrackerBETH.balanceOf(account);
    }
    
    function dividendTokenBalanceOfBTCB(address account) public view returns (uint256) {
        return dividendTrackerBTCB.balanceOf(account);
    }
    
    
    /// ----------------- getAccountDividendsInfo -------------------
    function getAccountDividendsInfo(address account)
    external view returns (
        address,
        int256,
        int256,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256) {
        return dividendTracker.getAccount(account);
    }
    
    function getAccountDividendsInfoBETH(address account)
    external view returns (
        address,
        int256,
        int256,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256) {
        return dividendTrackerBETH.getAccount(account);
    }
    
    function getAccountDividendsInfoBTCB(address account)
    external view returns (
        address,
        int256,
        int256,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256) {
        return dividendTrackerBTCB.getAccount(account);
    }
    
    
    /// ---------- getAccountDividendsInfoAtIndex ------------
    function getAccountDividendsInfoAtIndex(uint256 index)
    external view returns (
        address,
        int256,
        int256,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256) {
        return dividendTracker.getAccountAtIndex(index);
    }
    
     function getAccountDividendsInfoAtIndexBETH(uint256 index)
    external view returns (
        address,
        int256,
        int256,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256) {
        return dividendTrackerBETH.getAccountAtIndex(index);
    }
    
     function getAccountDividendsInfoAtIndexBTCB(uint256 index)
    external view returns (
        address,
        int256,
        int256,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256) {
        return dividendTrackerBTCB.getAccountAtIndex(index);
    }
    

    // function processDividendTracker(uint256 gas) external {
    //     (uint256 iterations, uint256 claims, uint256 lastProcessedIndex) = dividendTracker.process(gas);
    //     emit ProcessedDividendTracker(iterations, claims, lastProcessedIndex, false, gas, tx.origin);
    // }

    
    // --------- claim --------
    function claim() external {
        dividendTracker.processAccount(payable(msg.sender), false);
    }
    
    function claimBETH() external {
        dividendTrackerBETH.processAccount(payable(msg.sender), false);
    }
    
    function claimBTCB() external {
        dividendTrackerBTCB.processAccount(payable(msg.sender), false);
    }
    
    
    // ------- getLastProcessedIndex ------------
    function getLastProcessedIndex() external view returns(uint256) {
        return dividendTracker.getLastProcessedIndex();
    }
    
    function getLastProcessedIndexBETH() external view returns(uint256) {
        return dividendTrackerBETH.getLastProcessedIndex();
    }
    
    function getLastProcessedIndexBTCB() external view returns(uint256) {
        return dividendTrackerBTCB.getLastProcessedIndex();
    }
    
    
    /// ---------- getNumberOfDividendTokenHolders ------------
    function getNumberOfDividendTokenHolders() external view returns(uint256) {
        return dividendTracker.getNumberOfTokenHolders();
    }
    
    function getNumberOfDividendTokenHoldersBETH() external view returns(uint256) {
        return dividendTrackerBETH.getNumberOfTokenHolders();
    }
    
    function getNumberOfDividendTokenHoldersBTCB() external view returns(uint256) {
        return dividendTrackerBTCB.getNumberOfTokenHolders();
    }
    
    
    
   //Setter functions
   
    function excludeFromFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = true;
    }
    
    function includeInFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = false;
    }
    
    function setLiquidityTax(uint256 _tax) public onlyOwner {
        liquidityTax = _tax;
    }
    
    function setDividendTax(uint256 _tax) public onlyOwner {
        dividendTax = _tax;
    }
    
    function setMarketingTax(uint256 _tax) public onlyOwner {
        marketingTax = _tax;
    }
    
    function setDevTax(uint256 _tax) public onlyOwner {
        devTax = _tax;
    }
    
    function setBurnTax(uint256 _tax) public onlyOwner {
        burnTax = _tax;
    }
    
    function setBTCBdivisor(uint256 _divisor) public onlyOwner {
        require(_divisor <= 100, "Tina: % more than 100");
        BTCBdivisor = _divisor;
    }
    
    function setBETHdivisor(uint256 _divisor) public onlyOwner {
        require(_divisor <= 100, "Tina: % more than 100");
        BETHdivisor = _divisor;
    }
    
    function setBNBdivisor(uint256 _divisor) public onlyOwner {
        require(_divisor <= 100, "Tina: % more than 100");
        BNBdivisor = _divisor;
    }
    
    function setMarketingAddress(address _wallet) public onlyOwner {
        marketingAddress = _wallet;
    }
    
    function setDevAddress(address _wallet) public onlyOwner {
        devAddress = _wallet;
    }
}
