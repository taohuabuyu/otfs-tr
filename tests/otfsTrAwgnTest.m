classdef otfsTrAwgnTest < matlab.unittest.TestCase
    %otfsTrAwgnTest Non-hardware tests for TX-only AWGN injection.

    methods (TestClassSetup)
        function addProjectPath(testCase)
            projectRoot = fileparts(fileparts(mfilename("fullpath")));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                projectRoot));
        end
    end

    methods (Test)
        function testDisabledLeavesWaveformUnchanged(testCase)
            cfg = otfs_tr_config();
            cfg.enableTxAwgn = false;
            txSignal = complex(linspace(-0.2, 0.2, 1024).', ...
                linspace(0.2, -0.2, 1024).');

            [actual, info] = otfs_tr_add_tx_awgn(txSignal, cfg);

            testCase.verifyEqual(actual, txSignal);
            testCase.verifyFalse(info.enabled);
            testCase.verifyEqual(info.generatedNoisePower, 0, AbsTol=0);
        end

        function testEnabledNoiseIsDeterministicAndPreservesRng(testCase)
            cfg = otfs_tr_config();
            txSignal = 0.2*exp(1j*2*pi*(0:4095).'/37);
            originalRng = rng;

            [first, firstInfo] = otfs_tr_add_tx_awgn(txSignal, cfg);
            rngAfterFirst = rng;
            [second, secondInfo] = otfs_tr_add_tx_awgn(txSignal, cfg);

            testCase.verifyEqual(first, second);
            testCase.verifyEqual(firstInfo, secondInfo);
            testCase.verifyEqual(rngAfterFirst, originalRng);
        end

        function testEnabledNoiseMeetsSnrAndPeakLimit(testCase)
            cfg = otfs_tr_config();
            txSignal = [zeros(128, 1); ...
                0.2*exp(1j*2*pi*(0:3967).'/41)];

            [actual, info] = otfs_tr_add_tx_awgn(txSignal, cfg);
            transmittedClean = info.totalCommonScale*txSignal;
            transmittedNoise = actual-transmittedClean;
            measuredSnrDb = 10*log10(mean(abs(transmittedClean).^2) / ...
                mean(abs(transmittedNoise).^2));

            testCase.verifyTrue(info.enabled);
            testCase.verifyEqual(measuredSnrDb, cfg.txAwgnSnrDb, ...
                AbsTol=1e-10);
            testCase.verifyEqual(info.actualInjectedSnrDb, ...
                cfg.txAwgnSnrDb, AbsTol=1e-10);
            testCase.verifyLessThanOrEqual(max(abs(actual)), ...
                cfg.hardwareTxPeak+1e-12);
            testCase.verifyLessThanOrEqual(info.outputPower, ...
                info.originalSignalPower+1e-12);
            testCase.verifyGreaterThan(nnz(abs(actual(1:128)) > 0), 0);
        end

        function testDifferentSeedsProduceDifferentNoise(testCase)
            cfg = otfs_tr_config();
            txSignal = 0.2*ones(2048, 1);

            first = otfs_tr_add_tx_awgn(txSignal, cfg);
            cfg.txAwgnSeed = cfg.txAwgnSeed+1;
            second = otfs_tr_add_tx_awgn(txSignal, cfg);

            testCase.verifyNotEqual(first, second);
        end

        function testRejectsInvalidAwgnConfiguration(testCase)
            cfg = otfs_tr_config();
            cfg.txAwgnSnrDb = -1;

            testCase.verifyError(@() otfs_tr_validate_config(cfg), ...
                "otfs_tr:InvalidTxAwgnConfiguration");
        end
    end
end
