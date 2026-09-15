package itpu.uz.masterthesisobservability.aq;

import itpu.uz.masterthesisobservability.config.ObservabilityMode;
import itpu.uz.masterthesisobservability.config.ObservabilityProperties;
import jakarta.jms.ConnectionFactory;
import jakarta.jms.JMSException;
import lombok.extern.slf4j.Slf4j;
import oracle.jakarta.jms.AQjmsFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.jdbc.autoconfigure.DataSourceProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.sql.SQLException;

/**
 * Wires the Oracle AQ JMS client for {@link ObservabilityMode#AQ}.
 *
 * <p>The whole class is conditional on the active mode, so in every other run no AQ
 * connection, thread or meter is created at all. That matters for the experiment: a dormant
 * subscriber still holds a database session and still polls, and its cost would otherwise be
 * silently charged to whichever mode was being measured.
 */
@Configuration
@ConditionalOnProperty(name = "observability.mode", havingValue = "AQ")
@Slf4j
public class AqJmsConfiguration {

    /**
     * The AQ connection factory owns its DataSource privately. It is deliberately NOT a
     * Spring bean, and that is the single most important line in this class.
     *
     * <p><b>Why not a bean.</b> Declaring {@code @Bean DataSource} makes Spring Boot's
     * {@code DataSourceAutoConfiguration} back off, because it is guarded by
     * {@code @ConditionalOnMissingBean(DataSource.class)}. The whole application then ran on
     * this unpooled DataSource: HikariCP never started, every JDBC call opened a new physical
     * Oracle connection, the instance hit its {@code processes=200} ceiling, and 56% of HTTP
     * requests failed with ORA-12516. Nothing announced the loss of the pool — the
     * application started, reported healthy, and produced numbers that looked exactly like
     * "Advanced Queuing destroys OLTP throughput". Keeping the DataSource out of the context
     * removes the possibility entirely; {@code EnvironmentAssertions} then verifies at startup
     * that the OLTP pool really is pooled, so the failure can never again be silent.
     *
     * <p><b>Why unpooled.</b> AQ JMS casts the JDBC connection it is handed to
     * {@code oracle.jdbc.internal.OracleConnection} to reach the AQ protocol layer. A
     * HikariCP connection is a dynamic proxy, so the cast fails at startup with a
     * ClassCastException wrapped in "Error creating the db_connection". Any pool that wraps
     * rather than delegates is unusable here — a genuine integration constraint of Approach 1,
     * reported as part of its level of effort.
     *
     * <p><b>Why separate.</b> An AQ JMS session holds its database connection for the entire
     * life of the subscriber. Taking it from the OLTP pool would leave AQ mode running the
     * workload on 31 connections while every other mode had 32, and the throughput difference
     * would be read as a cost of Advanced Queuing when it was really pool starvation. The OLTP
     * pool stays identical in all modes; the extra session is reported as a cost of the
     * approach.
     */
    @Bean
    ConnectionFactory aqConnectionFactory(DataSourceProperties dataSourceProperties,
                                          ObservabilityProperties properties)
            throws JMSException, SQLException {
        var ds = new oracle.jdbc.datasource.impl.OracleDataSource();
        ds.setURL(dataSourceProperties.getUrl());
        ds.setUser(dataSourceProperties.getUsername());
        ds.setPassword(dataSourceProperties.getPassword());
        log.info("AQ JMS connection factory bound to {}.{} as durable subscriber {}",
                properties.aq().queueOwner(), properties.aq().queue(), properties.aq().subscriber());
        return AQjmsFactory.getConnectionFactory(ds);
    }
}
