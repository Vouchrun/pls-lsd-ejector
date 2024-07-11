VERSION := $(shell git describe --tags)
COMMIT  := $(shell git log -1 --format='%H')

all: build

LD_FLAGS = -X eth-lsd-ejector/cmd.Version=$(VERSION) \
	-X eth-lsd-ejector/cmd.Commit=$(COMMIT) \

BUILD_FLAGS := -ldflags '$(LD_FLAGS)'

get:
	@echo "  >  \033[32mDownloading & Installing all the modules...\033[0m "
	go mod tidy && go mod download

build:
	@echo " > \033[32mBuilding ETH LSD Ejector...\033[0m "
	go build -mod readonly $(BUILD_FLAGS) -o build/eth-lsd-ejector main.go

build-linux:
	@GOOS=linux GOARCH=amd64 go build --mod readonly $(BUILD_FLAGS) -o ./build/eth-lsd-ejector main.go

install: 
	@echo " > \033[32mInstalling ETH LSD Ejector...\033[0m "
	go install -mod readonly $(BUILD_FLAGS) ./...

clean:
	@echo " > \033[32mCleanning build files ...\033[0m "
	rm -rf build
fmt :
	@echo " > \033[32mFormatting go files ...\033[0m "
	go fmt ./...

abi:
	@echo " > \033[32mGenabi...\033[0m "
	abigen --abi ./bindings/Withdraw/withdraw_abi.json --pkg withdraw --type Withdraw --out ./bindings/Withdraw/Withdraw.go


get-lint:
	curl -sfL https://install.goreleaser.com/github.com/golangci/golangci-lint.sh | sh -s latest

lint:
	golangci-lint run ./... --skip-files ".+_test.go"

.PHONY: all lint test race msan tools clean build install
