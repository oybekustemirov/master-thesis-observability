package itpu.uz.masterthesisobservability.outbox;

import java.lang.annotation.*;

/**
 * Marks a business method whose successful completion is an A1 domain event.
 *
 * <p>The annotated method MUST be public, non-final, transactional, and invoked across a bean
 * boundary. AOP failures are silent by nature: a refactor that turns an external call into a
 * self-invocation removes the event with no error and no failing test. An ArchUnit rule
 * enforces those constraints at build time, and the aspect asserts transaction activity at
 * runtime, because "the event simply stopped being emitted" is the hardest defect to notice.
 */
@Target(ElementType.METHOD)
@Retention(RetentionPolicy.RUNTIME)
@Documented
public @interface EmitsEvent {

    /** Business event type, e.g. {@code A1TransactionValidated}. */
    String type();

    /** SpEL over method arguments and {@code #result}, e.g. {@code "#result.txnId()"}. */
    String aggregateId();

    String aggregateType() default "a1.transaction";

    /** SpEL producing the payload object. Defaults to the method's return value. */
    String payload() default "#result";
}
