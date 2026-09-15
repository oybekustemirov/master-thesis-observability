package itpu.uz.masterthesisobservability.outbox;

import itpu.uz.masterthesisobservability.config.ObservabilityProperties;
import itpu.uz.masterthesisobservability.metrics.TraceContext;
import lombok.RequiredArgsConstructor;
import org.aspectj.lang.ProceedingJoinPoint;
import org.aspectj.lang.annotation.Around;
import org.aspectj.lang.annotation.Aspect;
import org.aspectj.lang.reflect.MethodSignature;
import org.springframework.core.annotation.Order;
import org.springframework.expression.EvaluationContext;
import org.springframework.expression.spel.standard.SpelExpressionParser;
import org.springframework.expression.spel.support.StandardEvaluationContext;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionSynchronizationManager;

/**
 * Approach 2, variant B3. Ordered 200, which places it INSIDE the transaction advisor
 * (ordered 100 by {@code TransactionalEventingConfiguration}), so the outbox insert joins
 * the business transaction.
 */
@Aspect
@Component
@Order(200)
@RequiredArgsConstructor
public class EventEmittingAspect {

    private final EventEmitter emitter;
    private final ObservabilityProperties properties;
    private final TraceContext traceContext;
    private final SpelExpressionParser parser = new SpelExpressionParser();

    @Around("@annotation(emits)")
    public Object emit(ProceedingJoinPoint pjp, EmitsEvent emits) throws Throwable {
        Object result = pjp.proceed();

        if (!properties.mode().requiresOutboxWrites()
                && !properties.mode().publishesDirectly()) {
            return result;
        }

        // Guard against the silent regression described in TransactionalEventingConfiguration.
        // If aspect ordering ever breaks, this throws in CI rather than losing events in
        // production, where the symptom would be an unexplained gap in a reconciliation report.
        if (!TransactionSynchronizationManager.isActualTransactionActive()) {
            throw new IllegalStateException(
                    "@EmitsEvent on " + pjp.getSignature() + " executed outside an active "
                  + "transaction; the outbox write would not be atomic with the business write");
        }

        EvaluationContext context = evaluationContext(pjp, result);
        String aggregateId =
                String.valueOf(parser.parseExpression(emits.aggregateId()).getValue(context));
        Object payload = parser.parseExpression(emits.payload()).getValue(context);
        String traceId = traceContext.traceId();

        emitter.emit(A1Event.of(emits.type(), emits.aggregateType(), aggregateId,
                                traceId, payload));

        return result;
    }

    private EvaluationContext evaluationContext(ProceedingJoinPoint pjp, Object result) {
        var context = new StandardEvaluationContext();
        var signature = (MethodSignature) pjp.getSignature();
        String[] names = signature.getParameterNames();
        Object[] args = pjp.getArgs();
        if (names != null) {
            for (int i = 0; i < names.length; i++) {
                context.setVariable(names[i], args[i]);
            }
        }
        context.setVariable("result", result);
        return context;
    }
}
