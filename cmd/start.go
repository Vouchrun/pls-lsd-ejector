package cmd

import (
	"context"
	"eth-lsd-ejector/task"
	"fmt"
	"math"

	"github.com/ethereum/go-ethereum/common"
	"github.com/pkg/errors"
	"github.com/prysmaticlabs/prysm/v3/io/prompt"
	"github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
	"github.com/stafiprotocol/eth2-balance-service/shared"
	"github.com/stafiprotocol/eth2-balance-service/shared/beacon"
	"github.com/stafiprotocol/eth2-balance-service/shared/types"
)

const (
	flagKeysDir           = "keys_dir"
	flagExecutionEndpoint = "execution_endpoint"
	flagConsensusEndpoint = "consensus_endpoint"
	flagLogLevel          = "log_level"
	flagWithdrawAddress   = "withdraw_address"
)

// Keystore json file representation as a Go struct.
type Keystore struct {
	Crypto  map[string]interface{} `json:"crypto"`
	ID      string                 `json:"uuid"`
	Pubkey  string                 `json:"pubkey"`
	Version uint                   `json:"version"`
	Name    string                 `json:"name"`
	Path    string                 `json:"path"`
}

func startCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:     "start",
		Aliases: []string{"s"},
		Args:    cobra.ExactArgs(0),
		Short:   "Start ejector process",
		RunE: func(cmd *cobra.Command, args []string) error {
			keysDir, err := cmd.Flags().GetString(flagKeysDir)
			if err != nil {
				return err
			}
			if len(keysDir) == 0 {
				return fmt.Errorf("%s empty", flagKeysDir)
			}
			executionEndpoint, err := cmd.Flags().GetString(flagExecutionEndpoint)
			if err != nil {
				return err
			}
			if len(executionEndpoint) == 0 {
				return fmt.Errorf("%s empty", flagExecutionEndpoint)
			}
			consensusEndpoint, err := cmd.Flags().GetString(flagConsensusEndpoint)
			if err != nil {
				return err
			}
			if len(consensusEndpoint) == 0 {
				return fmt.Errorf("%s empty", flagConsensusEndpoint)
			}
			withdrawAddress, err := cmd.Flags().GetString(flagWithdrawAddress)
			if err != nil {
				return err
			}
			if !common.IsHexAddress(withdrawAddress) {
				return fmt.Errorf("parse withdraw address failed, address :%d", withdrawAddress)
			}
			logLevelStr, err := cmd.Flags().GetString(flagLogLevel)
			if err != nil {
				return err
			}
			logLevel, err := logrus.ParseLevel(logLevelStr)
			if err != nil {
				return err
			}
			logrus.SetLevel(logLevel)

			logrus.Infof("%s: %s", flagKeysDir, keysDir)
			logrus.Infof("%s: %s", flagExecutionEndpoint, executionEndpoint)
			logrus.Infof("%s: %s", flagConsensusEndpoint, consensusEndpoint)
			// interrupt signal
			ctx := ShutdownListener()

			keystores, err := parseKeysDir(keysDir)
			if err != nil {
				return errors.Wrap(err, "parseKeysDir failed")
			}
			if len(keystores) == 0 {
				return fmt.Errorf("no keystore found in directory %s", keysDir)
			}

			accountsPassword, err := prompt.PasswordPrompt(
				"Enter the password for your imported accounts", prompt.NotEmpty,
			)
			if err != nil {
				return fmt.Errorf("could not read account password: %w", err)
			}

			connection, err := shared.NewConnection(executionEndpoint, consensusEndpoint, nil, nil, nil)
			if err != nil {
				return errors.Wrap(err, "Start connection with endpoint failed")
			}

			// check rpc on start
			{
				block, err := connection.Eth1Client().BlockNumber(context.Background())
				if err != nil {
					return fmt.Errorf("check executionEndpoint: %s , request failed: %s", executionEndpoint, err.Error())
				}
				if block == 0 {
					return fmt.Errorf("check executionEndpoint: %s , request failed: latest block is zero", executionEndpoint)
				}

				beaconHead, err := connection.Eth2Client().GetBeaconHead()
				if err != nil {
					return fmt.Errorf("check consensusEndpoint: %s , request failed: %s", consensusEndpoint, err.Error())
				}

				if beaconHead.FinalizedEpoch == 0 {
					return fmt.Errorf("check consensusEndpoint: %s , request failed: finalized epoch is zero", consensusEndpoint)
				}
			}

			keys := map[string]string{}
			validators := make(map[uint64]*task.Validator)
			notExitValidators := make(map[string]*task.Validator, 0)
			for _, keystore := range keystores {
				privKeyBytes, pubKeyBytes, _, err := attemptDecryptKeystore(keystore, accountsPassword)
				if err != nil {
					return err
				}
				pubkey := types.BytesToValidatorPubkey(pubKeyBytes)

				// if key exists prior to being added then output log that duplicate key was found
				if _, ok := keys[pubkey.String()]; ok {
					logrus.Warnf("Duplicate key in import will be ignored: %#x", pubKeyBytes)
					continue
				}
				keys[pubkey.String()] = pubkey.String()
				beaconHead, err := connection.Eth2Client().GetBeaconHead()
				if err != nil {
					return err
				}

				status, err := connection.Eth2Client().GetValidatorStatus(pubkey, &beacon.ValidatorStatusOptions{Epoch: &beaconHead.FinalizedEpoch})
				if err != nil {
					return err
				}
				if !status.Exists {
					logrus.Infof("validator %s not exist, will check later", pubkey.String())
					validator := task.Validator{
						PrivateKey: privKeyBytes,
						Publickey:  pubKeyBytes,
					}
					notExitValidators[pubkey.String()] = &validator
					continue
				}
				// will skip if already sign exit
				if status.ExitEpoch != math.MaxUint64 {
					logrus.Infof("validator %s already exit, will skip", pubkey.String())
					continue
				}
				validator := task.Validator{
					ValidatorIndex: status.Index,
					PrivateKey:     privKeyBytes,
					Publickey:      pubKeyBytes,
				}
				validators[validator.ValidatorIndex] = &validator
				logrus.Debug("pubkeyHexString: ", pubkey.String())
			}

			logrus.Infof("find %d active validators", len(validators))

			t := task.NewTask(common.HexToAddress(withdrawAddress), validators, notExitValidators, connection)
			err = t.Start()
			if err != nil {
				return err
			}
			defer func() {
				logrus.Infof("shutting down task ...")
				t.Stop()
			}()

			<-ctx.Done()

			return nil
		},
	}

	cmd.Flags().String(flagKeysDir, "", "Path to a directory where keystores to be imported are stored (must provide)")
	cmd.Flags().String(flagExecutionEndpoint, "", "Execution node RPC provider endpoint (must provide)")
	cmd.Flags().String(flagConsensusEndpoint, "", "Consensus node RPC provider endpoint (must provide)")
	cmd.Flags().String(flagWithdrawAddress, "", "Network withdraw address")
	cmd.Flags().String(flagLogLevel, logrus.InfoLevel.String(), "The logging level (trace|debug|info|warn|error|fatal|panic)")
	return cmd
}
