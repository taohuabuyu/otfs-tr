classdef otfsTrParallelTest < matlab.unittest.TestCase
    %otfsTrParallelTest Verify frame-parallel detection matches serial output.

    methods (TestClassSetup)
        function addProjectPathAndStartPool(testCase)
            projectRoot = fileparts(fileparts(mfilename("fullpath")));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                projectRoot));
            testCase.assumeFalse(isempty(ver("parallel")), ...
                "Parallel Computing Toolbox is required.");
            pool = gcp("nocreate");
            if isempty(pool)
                pool = parpool("Processes", 2, ...
                    AdditionalPaths=projectRoot);
                testCase.addTeardown(@() delete(pool));
            end
        end
    end

    methods (Test)
        function testParallelDetectionMatchesSerial(testCase)
            % Arrange.
            serialCfg = otfsTrParallelTest.fastConfiguration();
            parallelCfg = serialCfg;
            parallelCfg.enableFrameParallel = true;
            parallelCfg.frameParallelWorkers = 2;
            parallelCfg.frameParallelMinimumFrames = 2;

            % Act.
            serialResult = otfs_tr_simulate_link( ...
                serialCfg, 600e3, Inf);
            parallelResult = otfs_tr_simulate_link( ...
                parallelCfg, 600e3, Inf);

            % Assert.
            testCase.verifyFalse(serialResult.frameParallelInfo.used);
            testCase.verifyTrue(parallelResult.frameParallelInfo.used);
            testCase.verifyFalse( ...
                parallelResult.frameParallelInfo.poolCreated);
            testCase.verifyEqual(parallelResult.validFrames, ...
                serialResult.validFrames);
            testCase.verifyEqual(parallelResult.frameIds, ...
                serialResult.frameIds);
            testCase.verifyEqual(parallelResult.frameBer, ...
                serialResult.frameBer, AbsTol=0);
            testCase.verifyEqual(parallelResult.totalBits, ...
                serialResult.totalBits);
            testCase.verifyEqual(parallelResult.totalErrors, ...
                serialResult.totalErrors);
            testCase.verifyEqual(parallelResult.ber, ...
                serialResult.ber, AbsTol=0);
            testCase.verifyEqual(parallelResult.headerCrcFailures, ...
                serialResult.headerCrcFailures);
            testCase.verifyEqual(parallelResult.duplicateFrameIds, ...
                serialResult.duplicateFrameIds);
            testCase.verifyEqual(parallelResult.sequenceDiscontinuities, ...
                serialResult.sequenceDiscontinuities);
            testCase.verifyEqual(vertcat( ...
                parallelResult.frameDiagnostics.bitErrors), ...
                vertcat(serialResult.frameDiagnostics.bitErrors));
        end

        function testParallelProgressUsesDataQueueAndCompletesJson(testCase)
            % Arrange.
            cfg = otfsTrParallelTest.fastConfiguration();
            cfg.enableFrameParallel = true;
            cfg.frameParallelWorkers = 2;
            cfg.frameParallelMinimumFrames = 2;
            cfg.enableProgressReporting = true;
            projectRoot = fileparts(fileparts(mfilename("fullpath")));
            progressDirectory = string(tempname(fullfile( ...
                projectRoot, "results")));
            mkdir(progressDirectory);
            testCase.addTeardown(@() rmdir(progressDirectory, "s"));
            cfg.progressFile = fullfile(progressDirectory, "progress.json");
            cfg.progressUpdateEveryBits = 2*cfg.effectiveBitsPerFrame;

            % Act.
            result = otfs_tr_simulate_link(cfg, 600e3, Inf);
            progress = jsondecode(fileread(cfg.progressFile));

            % Assert.
            testCase.verifyTrue(result.frameParallelInfo.used);
            testCase.verifyTrue( ...
                result.frameParallelInfo.progressDataQueueUsed);
            testCase.verifyGreaterThanOrEqual( ...
                result.frameParallelInfo.progressWriteCount, 2);
            testCase.verifyEqual(string(progress.stage), ...
                "detection_completed");
            testCase.verifyEqual(progress.completed_frames, ...
                progress.total_frames);
            testCase.verifyEqual(progress.completed_frames, ...
                result.attemptedFrames);
            testCase.verifyEqual(progress.valid_frames_so_far, ...
                result.validFrames);
            testCase.verifyEqual(progress.tested_bits_so_far, ...
                result.totalBits);
            testCase.verifyEqual(progress.bit_errors_so_far, ...
                result.totalErrors);
            testCase.verifyEqual(progress.ber_so_far, result.ber, ...
                AbsTol=0);
            testCase.verifyEqual(progress.ber_update_interval_bits, ...
                cfg.progressUpdateEveryBits);
            testCase.verifyEqual(progress.ber_update_count, 3);
            testCase.verifyFalse(logical(progress.is_ber_update));
            testCase.verifyEqual(result.frameParallelInfo. ...
                progressBerUpdateCount, 3);
            testCase.verifyEqual(result.frameParallelInfo. ...
                progressPublishedTestedBits, ...
                cfg.effectiveBitsPerFrame*(2:2:6).');
            testCase.verifyEqual(progress.progress_fraction, 1, ...
                AbsTol=0);
            testCase.verifyTrue(logical(progress.data_queue_used));
        end

        function testDefaultProgressIntervalIsOneHundredThousand(testCase)
            % Arrange.
            cfg = otfs_tr_config();

            % Act.
            actual = cfg.progressUpdateEveryBits;

            % Assert.
            testCase.verifyEqual(actual, 100000);
        end

        function testSharedMpCalibrationAvoidsSecondPass(testCase)
            % Arrange.
            cfg = otfsTrParallelTest.fastConfiguration();
            cfg.enableFrameParallel = true;
            cfg.frameParallelWorkers = 2;
            cfg.frameParallelMinimumFrames = 2;
            cfg.enableSharedMpNoiseCalibration = true;
            cfg.sharedMpNoiseCalibrationFrames = 2;
            cfg.sharedMpNoiseCalibrationMinimumValidFrames = 1;
            cfg.mpNoiseCalibrationMinRatio = 1;

            % Act.
            result = otfs_tr_simulate_link(cfg, 600e3, 25);
            sources = string({ ...
                result.frameDiagnostics.mpNoiseCalibrationSource});

            % Assert.
            testCase.verifyTrue(isfinite(result.frameParallelInfo. ...
                sharedMpNoiseCalibrationRatio));
            testCase.verifyEqual(result.frameParallelInfo. ...
                sharedMpNoiseCalibrationAppliedFrames, 4);
            testCase.verifyEqual(sum(sources == "shared"), 4);
            testCase.verifyEqual(result.sharedMpNoiseCalibrationFrames, 4);
            testCase.verifyEqual(result.totalErrors, 0);
            testCase.verifyEqual(result.validFrames, cfg.maxDecodedFrames);
        end

        function testRejectsInvalidWorkerCount(testCase)
            % Arrange.
            cfg = otfs_tr_config();
            cfg.frameParallelWorkers = 0;

            % Act.
            operation = @() otfs_tr_validate_config(cfg);

            % Assert.
            testCase.verifyError(operation, ...
                "otfs_tr:InvalidFrameParallelConfiguration");
        end

        function testRejectsInvalidMinimumFrameCount(testCase)
            % Arrange.
            cfg = otfs_tr_config();
            cfg.frameParallelMinimumFrames = 1;

            % Act.
            operation = @() otfs_tr_validate_config(cfg);

            % Assert.
            testCase.verifyError(operation, ...
                "otfs_tr:InvalidFrameParallelConfiguration");
        end


        function testRejectsInvalidProgressBitInterval(testCase)
            % Arrange.
            cfg = otfs_tr_config();
            cfg.progressUpdateEveryBits = 0;

            % Act.
            operation = @() otfs_tr_validate_config(cfg);

            % Assert.
            testCase.verifyError(operation, ...
                "otfs_tr:InvalidProgressConfiguration");
        end


        function testRejectsInvalidSharedCalibrationCounts(testCase)
            % Arrange.
            cfg = otfs_tr_config();
            cfg.sharedMpNoiseCalibrationFrames = 2;
            cfg.sharedMpNoiseCalibrationMinimumValidFrames = 3;

            % Act.
            operation = @() otfs_tr_validate_config(cfg);

            % Assert.
            testCase.verifyError(operation, ...
                "otfs_tr:InvalidSharedMpNoiseCalibrationConfiguration");
        end
    end

    methods (Static, Access=private)
        function cfg = fastConfiguration()
            cfg = otfs_tr_config();
            cfg.enableFrameParallel = false;
            cfg.enableFractionalTimingCompensation = false;
            cfg.superframeLength = 8;
            cfg.txBufferFrameCount = 8;
            cfg.txBurstLength = cfg.txBufferFrameCount*cfg.frameLength10;
            cfg.maxDecodedFrames = 6;
            cfg.captureCallCount = 1;
            cfg.captureBurstCount = 1;
            cfg.cfoSearchWindowSamples20 = 5000;
            cfg.cfoFineSearchStepHz = 500;
            cfg.frameResidualCfoSearchHz = -1000:100:1000;
            cfg.minimumTestBits = 1;
            cfg.minimumValidFrames = 1;
            cfg.totalUniquePayloadBits = cfg.superframeLength* ...
                cfg.effectiveBitsPerFrame;
        end
    end
end
