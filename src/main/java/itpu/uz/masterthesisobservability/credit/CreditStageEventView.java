package itpu.uz.masterthesisobservability.credit;

import java.math.BigDecimal;
import java.time.Instant;

/**
 * The payload published for one stage transition.
 *
 * <p>Carries the decomposition the process analysis depends on: the interval the case spent in
 * the stage, split into queue wait and work time. A consumer that receives only "stage X
 * completed at T" can compute an elapsed duration but cannot tell a staffing problem from a
 * tooling one, which is the distinction the whole analysis turns on.
 */
public record CreditStageEventView(
        String appRef,
        Long appId,
        String customerRef,
        String product,
        BigDecimal amount,
        String currency,
        String branchCode,
        boolean hasCollateral,
        String fromStage,
        String toStage,
        String stageName,
        String stageType,
        Instant enteredAt,
        Instant pickedUpAt,
        Instant completedAt,
        Long queueSeconds,
        Long workSeconds,
        String actorId,
        String actorRole,
        boolean rework,
        boolean terminal) {

    static CreditStageEventView of(CreditApplication app, String fromStage, String toStage,
                                   java.util.Map<String, Object> stage,
                                   Instant entered, Instant picked, Instant completed,
                                   String actorId, String actorRole,
                                   boolean rework, boolean terminal) {
        return new CreditStageEventView(
                app.getAppRef(), app.getAppId(), app.getCustomerRef(), app.getProduct(),
                app.getAmount(), app.getCurrency(), app.getBranchCode(),
                app.getHasCollateral() == 1,
                fromStage, toStage,
                String.valueOf(stage.get("STAGE_NAME")), String.valueOf(stage.get("STAGE_TYPE")),
                entered, picked, completed,
                picked == null ? null : java.time.Duration.between(entered, picked).toSeconds(),
                java.time.Duration.between(picked == null ? entered : picked, completed).toSeconds(),
                actorId, actorRole, rework, terminal);
    }
}
