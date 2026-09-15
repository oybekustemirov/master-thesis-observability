package itpu.uz.masterthesisobservability.config;

import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Configuration;
import org.springframework.transaction.annotation.EnableTransactionManagement;

/**
 * Spring registers its transaction advisor at {@code Ordered.LOWEST_PRECEDENCE} by default,
 * which makes it impossible for any other aspect to execute INSIDE the transaction. Lowering
 * it to 100 lets {@code EventEmittingAspect} (ordered 200) run within the transactional
 * boundary, so the outbox row and the business row share one commit.
 *
 * <p><b>This single integer is the difference between a zero-loss architecture (variant B3)
 * and a lossy one (variant B2).</b> It is invisible in code review unless you know to look
 * for it, which is why the aspect also asserts at runtime that a transaction is active.
 */
@Configuration
@EnableTransactionManagement(order = 100)
@EnableConfigurationProperties(ObservabilityProperties.class)
public class TransactionalEventingConfiguration { }
