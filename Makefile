-include .env #include eveything from .env

.phony:all test deploy #the targets are gonna use ,phoney fake 你明确告诉 Make：
#“这些目标（all、test、deploy）是虚拟的，不要检查文件是否存在，直接执行它们的命令”。
#这样无论目录下是否有同名文件，这些目标下的命令都会 强制运行。

build:; forge build

test:; forge test

install:; forge install cyfrin/foundry-devops@0.2.2 --no-commit && forge install smartcontractkit/chainlink-brownie-contracts@1.1.1 --no-commit && forge install foundry-rs/forge-std@v1.8.2 --no-commit && forge install transmissions11/solmate@v6.0.0 --no-commit
# for the people who want to copy this repor

deploy-sepolia:
	@forge script script/DeployRaffle.s.sol:DeployRaffle --rpc-url $(SEPOLIA_RPC_URL) --account Metamaske_Learning --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv