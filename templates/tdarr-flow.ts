const details = () => ({
  name: "Transcode Tuner Optimize",
  description:
    "Runs ttune to determine optimal encoding parameters for this file",
  stage: "Pre-processing",
  tags: "video,ffmpeg,optimization",
});

const plugin = async (args) => {
  const inputFile = args.inputFileObj._id;
  const result = await args.deps.cliExec(
    `ttune optimize -i "${inputFile}" --json --codec hevc --target-vmaf 95`,
  );
  const params = JSON.parse(result.stdout);
  args.variables.user.encoder = params.encoder;
  args.variables.user.crf = params.quality_param.split(" ").pop();
  args.variables.user.preset = String(params.preset);
  return {
    outputFileObj: args.inputFileObj,
    outputNumber: 1,
    variables: args.variables,
  };
};

module.exports = { details, plugin };
