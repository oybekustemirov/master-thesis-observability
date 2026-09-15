package itpu.uz.masterthesisobservability.metrics;

import io.micrometer.tracing.Tracer;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.stereotype.Component;

/**
 * Optional access to the current trace, so the application runs whether or not a tracing
 * backend is wired.
 *
 * <p>Trace correlation matters to this thesis: attaching the application's trace id to a
 * database-generated event is what turns Approach 1 from audit-grade into observability-grade
 * (see {@code OracleTraceContextPropagator}). But an unavailable tracer must degrade to a null
 * trace id, never prevent the experiment from running — an unmeasurable mode is worse than an
 * uncorrelated one.
 */
@Component
@RequiredArgsConstructor
public class TraceContext {

    private final ObjectProvider<Tracer> tracerProvider;

    public String traceId() {
        Tracer tracer = tracerProvider.getIfAvailable();
        if (tracer == null || tracer.currentSpan() == null) {
            return null;
        }
        return tracer.currentSpan().context().traceId();
    }

    public String spanId() {
        Tracer tracer = tracerProvider.getIfAvailable();
        if (tracer == null || tracer.currentSpan() == null) {
            return null;
        }
        return tracer.currentSpan().context().spanId();
    }
}
