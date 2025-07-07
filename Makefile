-include .env

# deps
update:; forge update
build  :; forge build
size  :; forge build --sizes

# storage inspection
inspect :; forge inspect ${contract} storage-layout --pretty

# if we want to run only matching tests, set that here
test := test_

# local tests without fork
test  :; forge test -vv 
trace  :; forge test -vvv 
gas  :; forge test 
test-contract  :; forge test -vv --match-contract $(contract) 
test-contract-gas  :; forge test --gas-report --match-contract $(contract)
trace-contract  :; forge test -vvv --match-contract $(contract) 
test-test  :; forge test -vv --match-test $(test) 
test-test-trace  :; forge test -vvv --match-test $(test) 
trace-test  :; forge test -vvvvv --match-test $(test) 
snapshot :; forge snapshot -vv 
snapshot-diff :; forge snapshot --diff -vv 
trace-setup  :; forge test -vvvv 
trace-max  :; forge test -vvvvv 
coverage :; forge coverage 
coverage-report :; forge coverage --report lcov 
coverage-debug :; forge coverage --report debug 


clean	:; forge clean
	
block:; export BLOCK=`cast block-number -r https://eth-mainnet.g.alchemy.com/v2/${API_KEY_ALCHEMY}`
