const { SNSClient, PublishCommand } = require("@aws-sdk/client-sns");
const snsClient = new SNSClient({ region: process.env.AWS_REGION });

const buildMessageRequest = (snsMessage, accountAlias, snsMessageFooter) => {
  return {
    version: "1.0",
    source: "custom",
    content: {
      textType: "client-markdown",
      title: snsMessage.AlarmName,
      description: `*Description*\n${snsMessage.AlarmDescription}\n*Reason*\n${snsMessage.NewStateReason}\n*Status*\n${snsMessage.NewStateValue}\n*Account*\n${snsMessage.AWSAccountId} ${accountAlias}\n${snsMessageFooter}`
    },
  };
};

// eslint-disable-next-line no-unused-vars
const handler = async function (event, context) {
  console.log("Alert lambda triggered");
  let accountAlias = process.env.ACCOUNT_ALIAS || "";
  let snsMessageFooter = process.env.MESSAGE_FOOTER || "GOV.UK Sign In alert";

  let snsMessage = JSON.parse(event.Records[0].Sns.Message);
  console.log(snsMessage);

  const messageRequest = buildMessageRequest(
    snsMessage,
    accountAlias,
    snsMessageFooter
  );

  console.log("Sending alert: %s to slack", messageRequest);
  try {
    const response = await snsClient.send(
      new PublishCommand({
        Message: JSON.stringify(messageRequest),
        TopicArn: process.env.NOTIFICATION_DETAILED_TOPIC_ARN,
        Subject: `${snsMessage.AlarmName} triggered in ${accountAlias}`
      })
    );
    console.log("SNS message %s published successfully", response.MessageId);
  } catch (error) {
    console.log(error);
  }
};

module.exports = { handler };
