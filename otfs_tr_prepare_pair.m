function pair = otfs_tr_prepare_pair(cfg)
%otfs_tr_prepare_pair Create an RX-owned directory for one link run.

pairRoot = fullfile(cfg.resultRoot, "pairs");
if ~exist(pairRoot, "dir")
    mkdir(pairRoot);
end

baseRunId = string(datetime("now", "Format", "yyyyMMdd_HHmmss_SSS"));
runId = baseRunId;
collisionIndex = 0;
pairDirectory = fullfile(pairRoot, runId);
while exist(pairDirectory, "dir")
    collisionIndex = collisionIndex + 1;
    runId = baseRunId + "_" + compose("%02d", collisionIndex);
    pairDirectory = fullfile(pairRoot, runId);
end

rxDirectory = fullfile(pairDirectory, "rx");
txDirectory = fullfile(pairDirectory, "tx");
reportDirectory = fullfile(pairDirectory, "reports");
mkdir(rxDirectory);
mkdir(txDirectory);
mkdir(reportDirectory);

pair = struct();
pair.version = 1;
pair.runId = runId;
pair.createdAt = string(datetime("now", ...
    "Format", "yyyy-MM-dd HH:mm:ss.SSS"));
pair.status = "waiting-for-capture";
pair.pairDirectory = string(pairDirectory);
pair.rxDirectory = string(rxDirectory);
pair.txDirectory = string(txDirectory);
pair.reportDirectory = string(reportDirectory);
pair.captureFile = string(fullfile(rxDirectory, "rx_capture.mat"));
pair.expectedReferenceFile = string(fullfile( ...
    txDirectory, "reference_package.mat"));
pair.manifestFile = string(fullfile(pairDirectory, "pair_manifest.mat"));

pairManifest = pair;
save(pair.manifestFile, "pairManifest");
end
