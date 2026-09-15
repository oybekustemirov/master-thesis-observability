package itpu.uz.masterthesisobservability.config;

import tools.jackson.databind.ObjectMapper;
import itpu.uz.masterthesisobservability.naive.AfterCommitEventEmitter;
import itpu.uz.masterthesisobservability.naive.DirectKafkaEventEmitter;
import itpu.uz.masterthesisobservability.outbox.*;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.kafka.core.KafkaTemplate;

/**
 * Selects exactly one emission strategy for the run. Constructing the strategies here rather
 * than component-scanning them guarantees that only the active one exists in the context, so
 * an inactive variant cannot contribute stray listeners, threads or metrics to a measurement.
 */
@Configuration
@Slf4j
public class EventEmitterConfiguration {

    @Bean
    EventEmitter eventEmitter(ObservabilityProperties properties,
                              OutboxWriter outboxWriter,
                              KafkaTemplate<String, String> kafka,
                              ObjectMapper objectMapper,
                              ApplicationEventPublisher publisher) {

        ObservabilityMode mode = properties.mode();
        EventEmitter emitter = switch (mode) {
            case WRAPPER_B3, HYBRID -> new OutboxEventEmitter(outboxWriter);
            case WRAPPER_B1 -> new DirectKafkaEventEmitter(kafka, objectMapper, properties);
            case WRAPPER_B2 -> new AfterCommitEventEmitter(publisher, kafka, objectMapper, properties);
            // AQ and CDC emit nothing from the application by design; OFF and BASELINE_GT
            // emit nothing at all.
            case OFF, BASELINE_GT, AQ, CDC -> new NoOpEventEmitter();
        };
        log.info("observability.mode={} -> emitter={}", mode, emitter.getClass().getSimpleName());
        return emitter;
    }
}
