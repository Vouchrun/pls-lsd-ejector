module eth-lsd-ejector

go 1.19

require (
	github.com/ethereum/go-ethereum v1.11.2
	github.com/pkg/errors v0.9.1
	github.com/prysmaticlabs/prysm/v3 v3.2.1
	github.com/sirupsen/logrus v1.9.0
	github.com/spf13/cobra v1.6.1
	github.com/stafiprotocol/eth2-balance-service v0.9.0
	github.com/wealdtech/go-eth2-wallet-encryptor-keystorev4 v1.1.3
)

require (
	github.com/beorn7/perks v1.0.1 // indirect
	github.com/btcsuite/btcd/btcec/v2 v2.2.1 // indirect
	github.com/cespare/xxhash/v2 v2.2.0 // indirect
	github.com/cpuguy83/go-md2man/v2 v2.0.2 // indirect
	github.com/deckarep/golang-set/v2 v2.1.0 // indirect
	github.com/decred/dcrd/dcrec/secp256k1/v4 v4.1.0 // indirect
	github.com/ferranbt/fastssz v0.0.0-20210905181407-59cf6761a7d5 // indirect
	github.com/fsnotify/fsnotify v1.6.0 // indirect
	github.com/gin-contrib/sse v0.1.0 // indirect
	github.com/gin-gonic/gin v1.8.1 // indirect
	github.com/go-ole/go-ole v1.2.6 // indirect
	github.com/go-playground/locales v0.14.0 // indirect
	github.com/go-playground/universal-translator v0.18.0 // indirect
	github.com/go-playground/validator/v10 v10.11.1 // indirect
	github.com/go-stack/stack v1.8.1 // indirect
	github.com/goccy/go-json v0.9.11 // indirect
	github.com/golang/protobuf v1.5.2 // indirect
	github.com/google/uuid v1.3.0 // indirect
	github.com/gorilla/websocket v1.5.0 // indirect
	github.com/grpc-ecosystem/grpc-gateway/v2 v2.0.1 // indirect
	github.com/hashicorp/golang-lru v0.5.5-0.20210104140557-80c98217689d // indirect
	github.com/herumi/bls-eth-go-binary v0.0.0-20210917013441-d37c07cfda4e // indirect
	github.com/inconshreveable/mousetrap v1.0.1 // indirect
	github.com/json-iterator/go v1.1.12 // indirect
	github.com/klauspost/cpuid/v2 v2.2.8 // indirect
	github.com/leodido/go-urn v1.2.1 // indirect
	github.com/logrusorgru/aurora v2.0.3+incompatible // indirect
	github.com/mattn/go-isatty v0.0.16 // indirect
	github.com/matttproud/golang_protobuf_extensions v1.0.4 // indirect
	github.com/minio/sha256-simd v1.0.0 // indirect
	github.com/mitchellh/mapstructure v1.4.2 // indirect
	github.com/modern-go/concurrent v0.0.0-20180306012644-bacd9c7ef1dd // indirect
	github.com/modern-go/reflect2 v1.0.2 // indirect
	github.com/mohae/deepcopy v0.0.0-20170929034955-c48cc78d4826 // indirect
	github.com/pelletier/go-toml/v2 v2.0.5 // indirect
	github.com/prometheus/client_golang v1.14.0 // indirect
	github.com/prometheus/client_model v0.3.0 // indirect
	github.com/prometheus/common v0.39.0 // indirect
	github.com/prometheus/procfs v0.9.0 // indirect
	github.com/prysmaticlabs/fastssz v0.0.0-20220628121656-93dfe28febab // indirect
	github.com/prysmaticlabs/go-bitfield v0.0.0-20210809151128-385d8c5e3fb7 // indirect
	github.com/prysmaticlabs/gohashtree v0.0.4-beta // indirect
	github.com/russross/blackfriday/v2 v2.1.0 // indirect
	github.com/satori/go.uuid v1.2.0 // indirect
	github.com/shirou/gopsutil v3.21.11+incompatible // indirect
	github.com/shopspring/decimal v1.3.1 // indirect
	github.com/spf13/pflag v1.0.5 // indirect
	github.com/stafiprotocol/chainbridge v0.0.0-20201204032253-9b92852c8d66 // indirect
	github.com/supranational/blst v0.3.10 // indirect
	github.com/thomaso-mirodin/intmath v0.0.0-20160323211736-5dc6d854e46e // indirect
	github.com/tklauser/go-sysconf v0.3.10 // indirect
	github.com/tklauser/numcpus v0.5.0 // indirect
	github.com/ugorji/go/codec v1.2.7 // indirect
	github.com/urfave/cli/v2 v2.17.2-0.20221006022127-8f469abc00aa // indirect
	github.com/wealdtech/go-eth2-types/v2 v2.6.0 // indirect
	github.com/xrash/smetrics v0.0.0-20201216005158-039620a65673 // indirect
	github.com/yusufpapurcu/wmi v1.2.2 // indirect
	golang.org/x/crypto v0.3.0 // indirect
	golang.org/x/net v0.4.0 // indirect
	golang.org/x/sync v0.1.0 // indirect
	golang.org/x/sys v0.25.0 // indirect
	golang.org/x/term v0.3.0 // indirect
	golang.org/x/text v0.7.0 // indirect
	google.golang.org/genproto v0.0.0-20210624195500-8bfb893ecb84 // indirect
	google.golang.org/grpc v1.40.0 // indirect
	google.golang.org/protobuf v1.28.1 // indirect
	gopkg.in/natefinch/npipe.v2 v2.0.0-20160621034901-c1b8fa8bdcce // indirect
	gopkg.in/yaml.v2 v2.4.0 // indirect
)

// See https://github.com/prysmaticlabs/grpc-gateway/issues/2
replace (
	github.com/ethereum/go-ethereum => github.com/gobitfly/go-ethereum v1.8.13-0.20230227100926-e78d720a0bf6
	github.com/grpc-ecosystem/grpc-gateway/v2 => github.com/prysmaticlabs/grpc-gateway/v2 v2.3.1-0.20210702154020-550e1cd83ec1
	github.com/prysmaticlabs/prysm/v3 => github.com/gobitfly/prysm/v3 v3.0.0-20230216184552-2f3f1e8190d5
)
