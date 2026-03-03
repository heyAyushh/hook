use crate::config::Config;
use crate::dlq::DlqProducer;
use crate::forwarder::Forwarder;
use anyhow::{Context, Result};
use rdkafka::ClientConfig;
use rdkafka::consumer::{CommitMode, Consumer, StreamConsumer};
use rdkafka::message::{BorrowedMessage, Message};
use relay_core::model::WebhookEnvelope;
use tracing::{error, info, warn};

pub struct KafkaConsumer {
    consumer: StreamConsumer,
    forwarder: Forwarder,
    dlq: DlqProducer,
}

impl KafkaConsumer {
    pub fn from_config(config: &Config, forwarder: Forwarder, dlq: DlqProducer) -> Result<Self> {
        let mut client_config = ClientConfig::new();
        client_config
            .set("bootstrap.servers", &config.kafka_brokers)
            .set("group.id", &config.kafka_group_id)
            .set("enable.auto.commit", "false")
            .set("auto.offset.reset", "latest")
            .set("security.protocol", &config.kafka_security_protocol);

        if let Some(mechanism) = &config.kafka_sasl_mechanism {
            client_config.set("sasl.mechanism", mechanism);
        }
        if let Some(username) = &config.kafka_sasl_username {
            client_config.set("sasl.username", username);
        }
        if let Some(password) = &config.kafka_sasl_password {
            client_config.set("sasl.password", password);
        }

        let consumer = client_config
            .create::<StreamConsumer>()
            .context("create kafka stream consumer")?;

        let topic_refs = config
            .kafka_topics
            .iter()
            .map(String::as_str)
            .collect::<Vec<_>>();
        consumer
            .subscribe(&topic_refs)
            .with_context(|| format!("subscribe to topics: {}", topic_refs.join(",")))?;

        Ok(Self {
            consumer,
            forwarder,
            dlq,
        })
    }

    pub async fn run(&self) -> Result<()> {
        info!("kafka-openclaw-hook started");

        loop {
            match self.consumer.recv().await {
                Ok(message) => {
                    if let Err(error) = self.process_message(message).await {
                        error!(error = %error, "failed to process kafka message");
                    }
                }
                Err(error) => {
                    warn!(error = %error, "kafka poll error");
                }
            }
        }
    }

    async fn process_message(&self, message: BorrowedMessage<'_>) -> Result<()> {
        let payload_bytes = message.payload().context("kafka message missing payload")?;

        let envelope: WebhookEnvelope = serde_json::from_slice(payload_bytes)
            .context("deserialize webhook envelope from kafka")?;

        if let Err(error) = self.forwarder.forward_with_retry(&envelope).await {
            warn!(
                event_id = %envelope.id,
                source = %envelope.source,
                error = %error,
                "forwarding failed, publishing to dlq"
            );
            self.dlq
                .publish_failed(&envelope, &error.to_string())
                .await
                .context("publish dlq envelope")?;
        } else {
            info!(
                event_id = %envelope.id,
                source = %envelope.source,
                event_type = %envelope.event_type,
                "forwarded to openclaw"
            );
        }

        self.consumer
            .commit_message(&message, CommitMode::Async)
            .context("commit kafka offset")?;

        Ok(())
    }
}
