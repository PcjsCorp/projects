
																		pragma solidity 0.8.10;

// SPDX-License-Identifier: MIT

import "./SafeERC20.sol";
import "./Ownable.sol";

interface IReferrals {
   function addMember(address investor, address sponsor) external;
   function getSponsor(address investor) external view returns (address);
   function getTeam(address sponsor, uint256 level) external view returns (uint256);
}

interface IVersion {
   function mapUserInfo(address investor) external view returns(uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256, bool);
   function totalBusiness(address investor) external view returns (uint256);
   function workingBonus(address investor) external view returns (uint256);
   function monthlySale(address investor, uint256 months) external view returns (uint256);
   
   function positionWiseTBC(uint256 stage, uint256 position) external view returns (uint256);
   function positionWiseWallet(uint256 stage, uint256 position) external view returns (address);
   function stageWiseUserTBC(uint256 stage, address investor) external view returns (uint256);
   
   function stageWiseAvailableTBC(uint256 stage) external view returns (uint256);
   function stageWiseCurrentSellPosition(uint256 stage) external view returns (uint256);
   function statusPerStage(uint256 stage) external view returns (bool);
}

contract InvestmentPlan is Ownable {
	using SafeERC20 for IERC20;
	
	address public TUSD;
	address public FundWallet;
	address public TreasuryWallet;
	IReferrals public Referrals;
	IVersion private V1;
	
	struct UserInfo {
       uint256 investedAmount;
	   uint256 levelIncome;
	   uint256 foreignTour;
	   uint256 monthlyReward;
	   uint256 workingBonus;
	   uint256 royaltyBonus;
	   uint256 receivedFromSale;
	   uint256 extraBonus;
	   uint256 claimedAmount;
	   uint256 claimedTBC;
	   bool royalty;
    }
	
	struct TBCHoldingInfo {
       uint256 totalTBC;
	   uint256 claimedTBC;
    }
	
	uint256 public royaltyIncentive;
	uint256 public nextRewardDrain;
	uint256 public workingBonusLoop;
    uint256 public monthlyBonusLoop;
	
	bool public saleEnable;
	
	uint256[10] public referralBonus = [500, 300, 200, 100, 100, 50, 50, 50, 50, 50];
	uint256[10] public teamRequiredForBonus = [0, 3, 3, 3, 3, 3, 3, 3, 3, 3];
	uint256[6] public investmentPackages = [100 * 10**18, 500 * 10**18, 1000 * 10**18, 2500 * 10**18, 5000 * 10**18, 10000 * 10**18];
	uint256[5] public pricePerStage = [1 * 10**18, 10 * 10**18, 100 * 10**18, 1000 * 10**18, 10000 * 10**18];
	uint256[6] public stageWiseAvailableTBC = [2500000 * 10**18, 2500000 * 10**18, 5000000 * 10**18, 5000000 * 10**18, 5000000 * 10**18];
	uint256[6] public stageWiseCurrentSellPosition = [0, 0, 0, 0, 0, 0];
	uint256[6] public incentivePerStage = [0, 4000, 4000, 5000, 5000, 5000];
	bool[6] public statusPerStage;
	
	mapping(address => TBCHoldingInfo) public mapTBCHoldingInfo;
	mapping(address => UserInfo) public mapUserInfo;
	mapping(address => uint256) public totalBusiness;
	mapping(address => uint256) public workingBonus;
	mapping(address => mapping(uint256 => uint256)) public monthlyPurchase;
	mapping(address => mapping(uint256 => uint256)) public monthlySale;
	mapping(address => mapping(uint256 => uint256)) public monthlySaleClaimed;
    mapping(uint256 => uint256[]) public positionWiseTBC;
	mapping(uint256 => address[]) public positionWiseWallet;
	mapping(uint256 => mapping(address => uint256)) public stageWiseUserTBC;
	mapping(uint256 => mapping(address => uint256[])) public stageWiseUserPosition;
	mapping(address => address) public mapNewAddress;
	
    constructor(address TUSDAddress, address fundWallet, address treasuryWallet, address VIAddress) {
	    require(TUSDAddress != address(0) && fundWallet != address(0) && treasuryWallet != address(0), "Zero address");
		
		royaltyIncentive = 1000;		
		nextRewardDrain = 1729974532;
		
		workingBonusLoop = 512;
        monthlyBonusLoop = 512;
		
		TUSD = address(TUSDAddress);
		FundWallet = address(fundWallet);
		TreasuryWallet = address(treasuryWallet);
		V1 = IVersion(VIAddress);
    }
	
	function buy(uint256 packages, uint256 buyStage, address investor, address sponsor, address communitySeller, uint256 stage2Share, uint256 stage3Share, uint256 stage4Share, uint256 stage5Share, uint256 stage6Share, uint256 holding) external {
	   require(sponsor != address(0), "Zero address");
	   require(address(Referrals) != address(0), "Referral address not added yet");
	   require(packages < investmentPackages.length, "Investment packages is not correct");
	   require(IERC20(TUSD).balanceOf(msg.sender) >= investmentPackages[packages], "TUSD balance not available for investment");
	   require(address(sponsor) != address(investor), "Investor and sponsor can't be same wallet");
	   
	   if(!saleEnable)
	   {
	      require(address(msg.sender) == owner(), "Sale is not started yet, only onwer can buy");
	   }
	   
	   uint256 investmentAmount = investmentPackages[packages];
	   IERC20(TUSD).safeTransferFrom(address(msg.sender), address(this), investmentAmount);
	   
	   if(address(Referrals.getSponsor(address(investor))) == address(0)) 
	   {
	       require(mapUserInfo[address(sponsor)].investedAmount > 0, "Sponsor is not correct");
		   Referrals.addMember(address(investor), address(sponsor));
	   }
	   sponsor = address(Referrals.getSponsor(address(investor)));
	   
	   uint256 totalTBC = (investmentAmount * 10**18) / (pricePerStage[buyStage]);
	   
	   require(statusPerStage[buyStage], "Stage is not active yet");
	   require(stageWiseAvailableTBC[buyStage] >= totalTBC, "TBC not available for sale");
	   
	   if(buyStage == 0)
	   {
		   require(stage2Share + stage3Share + stage4Share + stage5Share + stage6Share + holding == totalTBC, "Stagewise share is not correct");
		   updateStageWiseRecord(address(investor), stage2Share, stage3Share, stage4Share, stage5Share, stage6Share); 
	   }
	   else if(buyStage == 1)
	   {
		   require(stage3Share + stage4Share + stage5Share + stage6Share + holding == totalTBC, "Stagewise share is not correct");
		   updateStageWiseRecord(address(investor), 0, stage3Share, stage4Share, stage5Share, stage6Share); 
	   }
	   else if(buyStage == 2)
	   {
		   require(stage4Share + stage5Share + stage6Share + holding == totalTBC, "Stagewise share is not correct");
		   updateStageWiseRecord(address(investor), 0, 0, stage4Share, stage5Share, stage6Share);
	   }
	   else if(buyStage == 3)
	   {
		  require(stage5Share + stage6Share + holding == totalTBC, "Stagewise share is not correct");
		  updateStageWiseRecord(address(investor), 0, 0, 0, stage5Share, stage6Share);
	   }
	   else
	   {
		  require(stage6Share + holding == totalTBC, "Stagewise share is not correct");
		  updateStageWiseRecord(address(investor), 0, 0, 0, 0, stage6Share);
	   }
	   if(buyStage > 0)
	   {
	       updateStageWiseSell(address(communitySeller), buyStage, totalTBC);
	   }
	   if(block.timestamp >= nextRewardDrain)
	   {
	      nextRewardDrain += 30 days;
	   }
	   
	   stageWiseAvailableTBC[buyStage] -= totalTBC;
	   uint256 minimumTBCRequired = (investmentPackages[0] * 10**18) / (pricePerStage[buyStage]);
	   
	   if(minimumTBCRequired > stageWiseAvailableTBC[buyStage])
	   {
	      statusPerStage[buyStage + 1] = true;
	   }
	   
	   mapTBCHoldingInfo[address(investor)].totalTBC += holding;
	   
	   mapUserInfo[address(investor)].investedAmount += investmentAmount;
	   totalBusiness[address(sponsor)] += investmentAmount;
	   uint256 myDirect = Referrals.getTeam(address(sponsor), 0);
	   
	   if(myDirect >= 3 && totalBusiness[sponsor] >= (1500 * 10**18) && !mapUserInfo[sponsor].royalty)
	   {
	      mapUserInfo[address(sponsor)].royalty = true;
	   }
	   
	   monthlyPurchase[address(investor)][nextRewardDrain] += investmentAmount;
	   referralBonusDistribution(address(investor), investmentAmount);
	   workingBonusDistribution(address(investor), investmentAmount);
	   foreignTourBonusDistribution(address(sponsor), totalBusiness[sponsor]);
	   monthlyBonusDistribution(address(investor), investmentAmount);
	   
	   IERC20(TUSD).safeTransfer(address(TreasuryWallet), IERC20(TUSD).balanceOf(address(this)));
    }
	
	function setTeam(address[] calldata investor, address[] calldata sponsor) external onlyOwner {
	   require(!saleEnable, "Sale already started");
	   require(address(Referrals) != address(0), "Referral address not added yet");
	   
	   for(uint256 i = 0; i < investor.length; i++) 
	   {
	       address newInvestor = mapNewAddress[investor[i]] == address(0) ? investor[i] : mapNewAddress[investor[i]];
		   address newSponsor = mapNewAddress[sponsor[i]] == address(0) ? sponsor[i] : mapNewAddress[sponsor[i]];
	       if(address(Referrals.getSponsor(investor[i])) == address(0) && address(sponsor[i]) != address(0)) 
		   {
			  Referrals.addMember(address(newInvestor), address(newSponsor));
		   }
		   
		  (, , , uint256 monthlyReward, uint256 WBonus, uint256 royaltyBonus, uint256 receivedFromSale, uint256 extraBonus, uint256 claimedAmount, , ) = V1.mapUserInfo(address(investor[i]));

		   mapUserInfo[address(newInvestor)].monthlyReward = monthlyReward;
		   mapUserInfo[address(newInvestor)].workingBonus = WBonus;
		   mapUserInfo[address(newInvestor)].royaltyBonus = royaltyBonus;
		   mapUserInfo[address(newInvestor)].receivedFromSale = receivedFromSale;
		   mapUserInfo[address(newInvestor)].claimedAmount = claimedAmount;
		   mapUserInfo[address(newInvestor)].extraBonus = extraBonus;
		   
		   __setTeam(investor[i], address(newInvestor));
		   
		   monthlySale[address(newInvestor)][nextRewardDrain] = V1.monthlySale(address(investor[i]), nextRewardDrain);
		   workingBonus[address(newInvestor)] = V1.workingBonus(address(investor[i]));
		   totalBusiness[address(newInvestor)] = V1.totalBusiness(address(investor[i]));
	   }
  	}

	function __setTeam(address oldinvestor, address newinvestor) internal  {
	   (uint256 investedAmount, uint256 levelIncome, uint256 foreignTour, , , , , , , , bool royalty) = V1.mapUserInfo(address(oldinvestor));
	   
	    mapUserInfo[address(newinvestor)].investedAmount = investedAmount;
		mapUserInfo[address(newinvestor)].levelIncome = levelIncome;
		mapUserInfo[address(newinvestor)].foreignTour = foreignTour;
		mapUserInfo[address(newinvestor)].royalty = royalty;
	}

	function setSellPosition(uint256 stage, uint256 count) external onlyOwner{
	   require(!saleEnable, "Sale already started");
	   
	   uint256 startingPosition = positionWiseTBC[stage].length;
	   
	   for(uint256 i = startingPosition; i < (startingPosition + count); i++) 
	   {
	       address investor = V1.positionWiseWallet(stage, i);
		   address newInvestor = mapNewAddress[investor] == address(0) ? investor : mapNewAddress[investor];
		   
		   uint256 share = V1.positionWiseTBC(stage, i);
		   uint256 SWUTBC = V1.stageWiseUserTBC(stage, address(investor));
		   if(address(investor) != address(0))
		   {
		       stageWiseUserPosition[stage][address(newInvestor)].push(i);
	           positionWiseTBC[stage].push(share);
		       positionWiseWallet[stage].push(address(newInvestor));
			   stageWiseUserTBC[stage][address(newInvestor)] = SWUTBC;
		   }
	   }
  	}
	
	function setStageWiseData() external onlyOwner {
	   require(!saleEnable, "Sale already started");
	   
	   for(uint256 i= 0; i < stageWiseAvailableTBC.length; i++) 
	   {
	       stageWiseAvailableTBC[i] =  V1.stageWiseAvailableTBC(i);
		   stageWiseCurrentSellPosition[i] = V1.stageWiseCurrentSellPosition(i);
		   statusPerStage[i] = V1.statusPerStage(i);
	   }
  	}
	
	function startSale() external onlyOwner {
	   require(!saleEnable, "Sale already started");
	   saleEnable = true;
  	}
	
	function updateStageWiseSell(address communitySeller, uint256 stage, uint256 totalTBC) internal {
	
		uint256 communitySellLimit = totalTBC * 20 / 100;
		
		if(communitySeller != address(0))
		{
		    for(uint256 i= 0; i < stageWiseUserPosition[stage][address(communitySeller)].length; i++) 
			{
				uint256 sellerPosition = stageWiseUserPosition[stage][address(communitySeller)][i];
				uint256 remainingTBCOnPosition = positionWiseTBC[stage][sellerPosition];
				
				if(remainingTBCOnPosition > 0)
				{
					if(remainingTBCOnPosition >= communitySellLimit)
					{
						stageWiseUserTBC[stage][address(communitySeller)] -= communitySellLimit;
						positionWiseTBC[stage][sellerPosition] -= communitySellLimit;
						
						uint256 sellerFund = (communitySellLimit * pricePerStage[stage]) / (10**18);
						uint256 communityFund = (sellerFund * incentivePerStage[stage]) / 10000;
						
						mapUserInfo[address(communitySeller)].receivedFromSale += (sellerFund - communityFund);
						mapUserInfo[address(communitySeller)].claimedAmount += (sellerFund - communityFund);
						
						communitySellLimit = 0;
						if(saleEnable)
						{
						   IERC20(TUSD).safeTransfer(address(address(communitySeller)), (sellerFund - communityFund));
						}
						break;
					}
					else
					{
						 stageWiseUserTBC[stage][address(communitySeller)] -= remainingTBCOnPosition;
						 positionWiseTBC[stage][sellerPosition] = 0;
						 
						 uint256 sellerFund = (remainingTBCOnPosition * pricePerStage[stage]) / (10**18);
						 uint256 communityFund = (sellerFund * incentivePerStage[stage]) / 10000;
						 
						 mapUserInfo[address(communitySeller)].receivedFromSale += (sellerFund - communityFund);
						 mapUserInfo[address(communitySeller)].claimedAmount += (sellerFund - communityFund);
						 
						 communitySellLimit -= remainingTBCOnPosition;
						 if(saleEnable)
						 {
						    IERC20(TUSD).safeTransfer(address(address(communitySeller)), (sellerFund - communityFund));
						 }
					}
				}
			}
		}
		
		uint256 userSellLimit = (totalTBC * 30 / 100) + communitySellLimit;
		uint256 startingPosition = stageWiseCurrentSellPosition[stage];
		
		for(uint256 i = startingPosition; i < positionWiseTBC[stage].length; i++) 
		{
			uint256 remainingTBCOnPosition = positionWiseTBC[stage][i];
			
			if(remainingTBCOnPosition > 0)
			{
				if(remainingTBCOnPosition >= userSellLimit)
				{
					address userOnPosition = address(positionWiseWallet[stage][i]);
					
					stageWiseUserTBC[stage][userOnPosition] -= userSellLimit;
					positionWiseTBC[stage][i] -= userSellLimit;
					
					uint256 userFund = (userSellLimit * pricePerStage[stage]) / (10**18);
					uint256 communityFund = (userFund * incentivePerStage[stage]) / (10000);
					
					mapUserInfo[address(userOnPosition)].receivedFromSale += (userFund - communityFund);
					mapUserInfo[address(userOnPosition)].claimedAmount += (userFund - communityFund);
					
					if(saleEnable)
				    {
					   IERC20(TUSD).safeTransfer(userOnPosition, (userFund - communityFund));
					}
					stageWiseCurrentSellPosition[stage] = i;
					break;
				}
				else
				{
					address userOnPosition = address(positionWiseWallet[stage][i]);
					
					stageWiseUserTBC[stage][userOnPosition] -= remainingTBCOnPosition;
					positionWiseTBC[stage][i] = 0;
					
					uint256 userFund = (remainingTBCOnPosition * pricePerStage[stage]) / (10**18);
					uint256 communityFund = (userFund * incentivePerStage[stage]) / (10000);
					
					mapUserInfo[address(userOnPosition)].receivedFromSale += (userFund - communityFund);
					mapUserInfo[address(userOnPosition)].claimedAmount += (userFund - communityFund);
					
					userSellLimit -= remainingTBCOnPosition;
					stageWiseCurrentSellPosition[stage] = i;
					if(saleEnable)
				    {
					   IERC20(TUSD).safeTransfer(userOnPosition, (userFund - communityFund));
					}
				}
			}
		}
	}
	
	function updateStageWiseRecord(address investor, uint256 stage2Share, uint256 stage3Share, uint256 stage4Share, uint256 stage5Share, uint256 stage6Share) internal {
	   if(stage2Share > 0) 
	   {
	      stageWiseUserPosition[1][address(investor)].push(positionWiseTBC[1].length);
		  positionWiseTBC[1].push(stage2Share);
		  positionWiseWallet[1].push(address(investor));
		  
		  stageWiseAvailableTBC[1] += stage2Share;
		  stageWiseUserTBC[1][address(investor)] += stage2Share;
	   }
	   if(stage3Share > 0) 
	   {
	      stageWiseUserPosition[2][address(investor)].push(positionWiseTBC[2].length);
		  positionWiseTBC[2].push(stage3Share);
		  positionWiseWallet[2].push(address(investor));
		  
		  stageWiseAvailableTBC[2] += stage3Share;
		  stageWiseUserTBC[2][address(investor)] += stage3Share;
	   }
	   if(stage4Share > 0) 
	   {
	      stageWiseUserPosition[3][address(investor)].push(positionWiseTBC[3].length);
		  positionWiseTBC[3].push(stage4Share);
		  positionWiseWallet[3].push(address(investor));
		  
		  stageWiseAvailableTBC[3] += stage4Share;
		  stageWiseUserTBC[3][address(investor)] += stage4Share;
	   }
	   if(stage5Share > 0) 
	   {
	      stageWiseUserPosition[4][address(investor)].push(positionWiseTBC[4].length);
		  positionWiseTBC[4].push(stage5Share);
		  positionWiseWallet[4].push(address(investor));
		  
		  stageWiseAvailableTBC[4] += stage5Share;
		  stageWiseUserTBC[4][address(investor)] += stage5Share;
	   }
	   if(stage6Share > 0) 
	   {
	      stageWiseUserPosition[5][address(investor)].push(positionWiseTBC[5].length);
		  positionWiseTBC[5].push(stage6Share);
		  positionWiseWallet[5].push(address(investor));
		  
		  stageWiseAvailableTBC[5] += stage6Share;
		  stageWiseUserTBC[5][address(investor)] += stage6Share;
	   }
	}
	
	function referralBonusDistribution(address investor, uint256 amount) internal {
		address sponsor = Referrals.getSponsor(investor);
		
		for(uint256 i=0; i < 10; i++) 
		{
			if(address(sponsor) != address(0)) 
			{   
			    uint256 myDirect = Referrals.getTeam(address(sponsor), 0);
			    if(myDirect >= teamRequiredForBonus[i])
				{
				   address sponsorWallet = address(Referrals.getSponsor(sponsor));
				   if(i==0 && myDirect >= 5)
				   {
				        uint256 reward = amount * (referralBonus[i] * 2) / 10000;
						if(mapUserInfo[sponsorWallet].royalty)
						{
						   royaltyBonusDistribution(sponsorWallet, ((reward * royaltyIncentive) / 10000));
						}
					    mapUserInfo[address(sponsor)].levelIncome += reward;
			            mapUserInfo[address(sponsor)].claimedAmount += reward;
						if(saleEnable)
						{
						   IERC20(TUSD).safeTransfer(address(sponsor), reward);
						}
				   }
				   else
				   {
     				   if(i==0)
					   {
					        uint256 reward = amount * referralBonus[i] / 10000;
							if(mapUserInfo[sponsorWallet].royalty)
							{
							   royaltyBonusDistribution(sponsorWallet, ((reward * royaltyIncentive) / 10000));
							}
						    mapUserInfo[sponsor].levelIncome += reward;
			                mapUserInfo[sponsor].claimedAmount += reward;
							if(saleEnable)
						    {
							   IERC20(TUSD).safeTransfer(address(sponsor), reward);
							}
					   }
					   else if(totalBusiness[address(sponsor)] >= (1500 * 10**18))
					   { 
					       uint256 reward = amount * referralBonus[i] / 10000;
						   if(mapUserInfo[sponsorWallet].royalty)
						   {
							  royaltyBonusDistribution(sponsorWallet, ((reward * royaltyIncentive) / 10000));
						   }
						   mapUserInfo[sponsor].levelIncome += reward;
			               mapUserInfo[sponsor].claimedAmount += reward;
						   if(saleEnable)
						   {
						      IERC20(TUSD).safeTransfer(address(sponsor), reward);
						   }
					   }
				   }
				}
			}
			else 
			{
		       break;
			}
		    sponsor = Referrals.getSponsor(sponsor);
		}
    }
	
	function monthlyBonusDistribution(address investor, uint256 amount) internal {
	    address sponsor = Referrals.getSponsor(investor);
		for(uint256 i=0; i < monthlyBonusLoop; i++) 
		{
			if(sponsor != address(0)) 
			{ 
			    monthlySale[address(sponsor)][nextRewardDrain] += amount;
			}
			else 
			{
		       break;
			}
		    sponsor = Referrals.getSponsor(sponsor);
		}
	}
	
	function workingBonusDistribution(address investor, uint256 amount) internal {
	    address sponsor = Referrals.getSponsor(investor);
		for(uint256 i=0; i < workingBonusLoop; i++) 
		{
			if(address(sponsor) != address(0)) 
			{   
				if(workingBonus[address(sponsor)] > 0)
				{
				    uint256 payableAmount = amount * (workingBonus[address(sponsor)]) / 10000;
					if(IERC20(TUSD).balanceOf(address(this)) >= payableAmount)
					{
					    mapUserInfo[address(sponsor)].workingBonus += payableAmount;
					    mapUserInfo[sponsor].claimedAmount += payableAmount;
						if(saleEnable)
						{
						   IERC20(TUSD).safeTransfer(address(sponsor), payableAmount);
						}
					    break;
					}
					else if(IERC20(TUSD).allowance(address(FundWallet), address(this)) >= payableAmount && IERC20(TUSD).balanceOf(address(FundWallet)) >= payableAmount)
					{
					    mapUserInfo[address(sponsor)].workingBonus += payableAmount;
					    mapUserInfo[sponsor].claimedAmount += payableAmount;
						if(saleEnable)
						{
						   IERC20(TUSD).safeTransferFrom(address(FundWallet), address(sponsor), payableAmount);
						}
					    break;
					}
					else
					{
					    mapUserInfo[address(sponsor)].workingBonus += payableAmount;
					    break;
					}
				}
			}
			else 
			{
		       break;
			}
		    sponsor = Referrals.getSponsor(sponsor);
		}
	}
	
	function foreignTourBonusDistribution(address sponsor, uint256 amount) internal {
	
	   uint256 incentiveAmount = (amount / (3000 * 10**18)) * (300 * 10**18);
	   
	   if(incentiveAmount > mapUserInfo[sponsor].foreignTour)
	   {
	       uint256 payableAmount = incentiveAmount - mapUserInfo[sponsor].foreignTour;
		   if(mapUserInfo[Referrals.getSponsor(sponsor)].royalty)
		   {
			  royaltyBonusDistribution(Referrals.getSponsor(sponsor), ((payableAmount * royaltyIncentive) / 10000));
		   }
		   if(IERC20(TUSD).balanceOf(address(this)) >= payableAmount)
		   {
		       mapUserInfo[sponsor].foreignTour += payableAmount;
			   mapUserInfo[sponsor].claimedAmount += payableAmount;
			   if(saleEnable)
			   {
			     IERC20(TUSD).safeTransfer(address(sponsor), payableAmount);
			   }
		   }
		   else if(IERC20(TUSD).allowance(address(FundWallet), address(this)) >= payableAmount && IERC20(TUSD).balanceOf(address(FundWallet)) >= payableAmount)
		   {
		       mapUserInfo[sponsor].foreignTour += payableAmount;
			   mapUserInfo[sponsor].claimedAmount += payableAmount;
			   if(saleEnable)
			   {
			      IERC20(TUSD).safeTransferFrom(address(FundWallet), address(sponsor), payableAmount);
			   }
		   }
		   else
		   {
		      mapUserInfo[sponsor].foreignTour += payableAmount;
		   }
	   }
	}
	
	function royaltyBonusDistribution(address sponsor, uint256 payableAmount) internal {
	    if(address(sponsor) != address(0))
		{
		    if(IERC20(TUSD).balanceOf(address(this)) >= payableAmount)
			{
				mapUserInfo[sponsor].royaltyBonus += payableAmount;
				mapUserInfo[sponsor].claimedAmount += payableAmount;
				if(saleEnable)
				{
				   IERC20(TUSD).safeTransfer(address(sponsor), payableAmount);
				}
			}
			else if(IERC20(TUSD).allowance(address(FundWallet), address(this)) >= payableAmount && IERC20(TUSD).balanceOf(address(FundWallet)) >= payableAmount)
			{
				mapUserInfo[sponsor].royaltyBonus += payableAmount;
				mapUserInfo[sponsor].claimedAmount += payableAmount;
				if(saleEnable)
				{
				   IERC20(TUSD).safeTransferFrom(address(FundWallet), address(sponsor), payableAmount);
				}
			}
			else
			{
				mapUserInfo[sponsor].royaltyBonus += payableAmount;
			} 
		}
	}
	
	function claimMonthlyReward(address topSponsor, uint256 month) external {
	    require(monthlySaleClaimed[address(msg.sender)][month] == 0, "Monthly reward already claimed");
	    require(Referrals.getSponsor(topSponsor) == address(msg.sender), "Top sponsor is not correct");
		
	    uint256 topSponsorSale = (monthlySale[address(topSponsor)][month]) + (monthlyPurchase[address(topSponsor)][month]);
	    uint256 allSale = monthlySale[address(msg.sender)][month];
	    uint256 remainingTeamSale = allSale - topSponsorSale;
		
	    uint256 payableAmount = 0;
		if(topSponsorSale >= (10000000 * 10**18) && remainingTeamSale >= (10000000 * 10**18))
		{
		    payableAmount = 1000000 * 10**18;
		}
		else if(topSponsorSale >= (5000000 * 10**18) && remainingTeamSale >= (5000000 * 10**18))
		{
			payableAmount = 400000 * 10**18;
		}
		else if(topSponsorSale >= (2000000 * 10**18) && remainingTeamSale >= (2000000 * 10**18))
		{
			payableAmount = 150000 * 10**18;
		}
		else if(topSponsorSale >= (500000 * 10**18) && remainingTeamSale >= (500000 * 10**18))
		{
			payableAmount = 35000 * 10**18;
		}
		else if(topSponsorSale >= (125000 * 10**18) && remainingTeamSale >= (125000 * 10**18))
		{
			payableAmount = 8500 * 10**18;
		}
		else if(topSponsorSale >= (50000 * 10**18) && remainingTeamSale >= (50000 * 10**18))
		{
			payableAmount = 3000 * 10**18;
		}
		else if(topSponsorSale >= (15000 * 10**18) && remainingTeamSale >= (15000 * 10**18))
		{
		    payableAmount = 800 * 10**18;
		}
		else if(topSponsorSale >= (5000 * 10**18) && remainingTeamSale >= (5000 * 10**18))
		{
		    payableAmount = 250 * 10**18;
		}
		
		if(payableAmount > 0 && IERC20(TUSD).allowance(address(FundWallet), address(this)) >= payableAmount && IERC20(TUSD).balanceOf(address(FundWallet)) >= payableAmount)
		{
		    monthlySaleClaimed[address(msg.sender)][month] = 1;
		    address sponsor = Referrals.getSponsor(address(msg.sender));
		    if(mapUserInfo[sponsor].royalty)
		    {
			   royaltyBonusDistribution(sponsor, ((payableAmount * royaltyIncentive) / 10000));
		    }
			mapUserInfo[address(msg.sender)].monthlyReward += payableAmount;
			mapUserInfo[address(msg.sender)].claimedAmount += payableAmount;
		    IERC20(TUSD).safeTransferFrom(address(FundWallet), address(msg.sender), payableAmount);
		}
		if(topSponsorSale >= (15000 * 10**18) && remainingTeamSale >= (15000 * 10**18) && workingBonus[address(msg.sender)] == 0)
		{
		   workingBonus[address(msg.sender)] = 500;
		}
	}
	
	function withdrawEarning(uint256 amount) external {
	
		uint256 payableAmount = pendingReward(address(msg.sender));
		if(payableAmount >= amount && IERC20(TUSD).allowance(address(FundWallet), address(this)) >= amount && IERC20(TUSD).balanceOf(address(FundWallet)) >= amount)
		{
		    mapUserInfo[address(msg.sender)].claimedAmount += amount;
		    IERC20(TUSD).safeTransferFrom(address(FundWallet), address(msg.sender), amount);
		}
	}
	
	function claimHoldingTBC() external {
		uint256 total = mapTBCHoldingInfo[address(msg.sender)].totalTBC;
		uint256 claimed = mapTBCHoldingInfo[address(msg.sender)].claimedTBC;
		uint256 claimable = total - claimed;
		uint256 balance = address(this).balance;
		if(claimable > 0 &&  balance >= claimable)
		{
		    payable(msg.sender).transfer(claimable);
		    mapTBCHoldingInfo[address(msg.sender)].claimedTBC += claimable;
		}
	}
	
	function updateTeam(address[] calldata oldAddress, address[] calldata newAddress) external onlyOwner {
	   for(uint256 i = 0; i < oldAddress.length; i++) 
	   {
	       if(oldAddress[i] != address(0) && newAddress[i] != address(0))
		   {
		      mapNewAddress[oldAddress[i]] = newAddress[i];
		   }
	   }
  	}
	
	function pendingReward(address user) public view returns (uint256) {
		if(mapUserInfo[address(user)].investedAmount > 0) 
		{
            uint256 pending = (mapUserInfo[address(user)].levelIncome + mapUserInfo[address(user)].foreignTour + mapUserInfo[address(user)].workingBonus + mapUserInfo[address(user)].royaltyBonus + mapUserInfo[address(user)].monthlyReward + mapUserInfo[address(user)].receivedFromSale + mapUserInfo[address(user)].extraBonus) - (mapUserInfo[address(user)].claimedAmount);
		    return pending;
        } 
		else 
		{
		   return 0;
		}
    }
	
	function claimTBC() external {
	   require(statusPerStage[5], "Exchange stage is not start yet");
	   
	   uint256 claimableTBC = stageWiseUserTBC[5][address(msg.sender)] - mapUserInfo[address(msg.sender)].claimedTBC;
	   uint256 balance = address(this).balance;
	   if(claimableTBC > 0 && balance >= claimableTBC)
	   {
	       payable(msg.sender).transfer(claimableTBC);
		   mapUserInfo[address(msg.sender)].claimedTBC += claimableTBC;
	   }
  	}
	
	function addReferral(address referral) external onlyOwner {
	   require(address(Referrals) == address(0), "Zero address");
	   
	   Referrals = IReferrals(referral);
    }
	
	function setWorkingBonus(address topSponsor, uint256 month) external {
	   require(Referrals.getSponsor(topSponsor) == address(msg.sender), "Top sponsor is not correct");
	   require(workingBonus[address(msg.sender)] == 0, "Working bonus already set");
	   
	   uint256 topSponsorSale = (monthlySale[address(topSponsor)][month]) + (monthlyPurchase[address(topSponsor)][month]);
	   uint256 allSale = monthlySale[address(msg.sender)][month];
	   uint256 remainingTeamSale = allSale - topSponsorSale;
	   
	   if(topSponsorSale >= (15000 * 10**18) && remainingTeamSale >= (15000 * 10**18))
	   {
		  workingBonus[address(msg.sender)] = 500;
	   }
  	}
}
																	