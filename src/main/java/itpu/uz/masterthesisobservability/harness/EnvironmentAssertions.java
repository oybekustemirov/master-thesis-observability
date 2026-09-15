package itpu.uz.masterthesisobservability.harness;

import com.zaxxer.hikari.HikariDataSource;
import itpu.uz.masterthesisobservability.config.ObservabilityProperties;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;

import javax.sql.DataSource;

/**
 * Refuses to start a measurement run in an environment that would produce meaningless numbers.
 *
 * <p>This exists because of a real incident. Adding an {@code @Bean DataSource} for the AQ
 * bridge silently disabled Spring Boot's DataSource auto-configuration, so the application ran
 * with no connection pool: a new physical Oracle connection per JDBC call, the instance's
 * {@code processes=200} ceiling reached, and 56% of requests failing with ORA-12516. The
 * application still started and still reported healthy. The resulting measurements were not
 * merely noisy — they were a fabricated performance catastrophe attributable to Advanced
 * Queuing, which had nothing to do with it.
 *
 * <p>A run that cannot be trusted must fail loudly at second zero rather than produce a
 * plausible-looking CSV row three minutes later. Every condition checked here is one that is
 * invisible in the application's own health output.
 */
@Component
@RequiredArgsConstructor
@Order(0)
@Slf4j
public class EnvironmentAssertions implements ApplicationRunner {

    /** Below this the OLTP pool is not the pool the experiment was configured with. */
    private static final int MIN_EXPECTED_POOL_SIZE = 8;

    private final DataSource dataSource;
    private final ObservabilityProperties properties;

    @Override
    public void run(ApplicationArguments args) {
        if (!(dataSource instanceof HikariDataSource hikari)) {
            throw new IllegalStateException(
                    "OLTP DataSource is " + dataSource.getClass().getName() + ", not a pooled "
                  + "HikariDataSource. Spring Boot's DataSourceAutoConfiguration has been "
                  + "disabled by another DataSource bean in the context. Every measurement "
                  + "taken in this state would be invalid.");
        }
        int poolSize = hikari.getMaximumPoolSize();
        if (poolSize < MIN_EXPECTED_POOL_SIZE) {
            throw new IllegalStateException(
                    "OLTP pool size is " + poolSize + ", below the expected minimum of "
                  + MIN_EXPECTED_POOL_SIZE + ". Modes must be compared at an identical pool "
                  + "size or the difference measured is pool starvation, not the mechanism.");
        }
        // Logged so that every run's app.log records the pool the numbers were produced with.
        log.info("environment ok: mode={} oltpPool={} maxSize={}",
                properties.mode(), hikari.getPoolName(), poolSize);
    }
}
