package itpu.uz.masterthesisobservability.api;

import itpu.uz.masterthesisobservability.credit.CreditApplicationNotFoundException;
import itpu.uz.masterthesisobservability.credit.CreditApplicationService;
import itpu.uz.masterthesisobservability.credit.CreditQueryService;
import itpu.uz.masterthesisobservability.credit.CreditStaffQueryService;
import itpu.uz.masterthesisobservability.credit.CreditStageEventView;
import itpu.uz.masterthesisobservability.credit.UnknownStageException;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;
import java.time.Instant;

/** Drives a credit application through its stages. Each call produces exactly one event through
    whichever capture mechanism the run is configured with. */
@RestController
@RequestMapping("/api/credit")
@RequiredArgsConstructor
public class CreditController {

    private final CreditApplicationService service;
    private final CreditQueryService queries;
    private final CreditStaffQueryService staffQueries;

    public record SubmitRequest(String appRef, String customerRef, String product,
                                BigDecimal amount, String currency, String channel,
                                String branchCode, Boolean collateral, String actorId) {}

    /** enteredAt is when the case ARRIVED in the stage it is now leaving — usually the previous
        transition's completion, which is why the caller supplies it rather than the server
        assuming "now". */
    public record AdvanceRequest(String toStage, Instant enteredAt, Instant pickedUpAt,
                                 Instant completedAt, String actorId, String actorRole,
                                 Boolean rework) {}

    @GetMapping("/staff")
    public Object staff() { return staffQueries.staff(); }

    @GetMapping("/staff/{staffId}")
    public Object staffCases(@PathVariable String staffId) { return staffQueries.byStaff(staffId); }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public CreditStageEventView submit(@RequestBody SubmitRequest r) {
        return service.submit(r.appRef(), r.customerRef(), r.product(), r.amount(),
                r.currency(), r.channel(), r.branchCode(),
                Boolean.TRUE.equals(r.collateral()), r.actorId());
    }

    @PostMapping("/{appRef}/advance")
    public CreditStageEventView advance(@PathVariable String appRef, @RequestBody AdvanceRequest r) {
        return service.advance(appRef, r.toStage(), r.enteredAt(), r.pickedUpAt(),
                r.completedAt(), r.actorId(), r.actorRole(), Boolean.TRUE.equals(r.rework()));
    }

    @GetMapping("/{appRef}")
    public CreditApplicationSummary find(@PathVariable String appRef) {
        var a = service.find(appRef);
        return new CreditApplicationSummary(a.getAppRef(), a.getProduct(), a.getAmount(),
                a.getBranchCode(), a.getCurrentStage(), a.getOutcome(),
                a.getSubmittedAt(), a.getClosedAt(), a.getHasCollateral() == 1);
    }

    public record CreditApplicationSummary(String appRef, String product, BigDecimal amount,
                                           String branchCode, String currentStage, String outcome,
                                           Instant submittedAt, Instant closedAt,
                                           boolean hasCollateral) {}

    // ------------------------------------------------------------- read side ----
    // Feeds the operations view. Separate from the command endpoints because they answer to
    // different people: the POSTs are the workflow, these are the people asking what it cost.

    @GetMapping("/applications")
    public java.util.List<java.util.Map<String, Object>> applications(
            @RequestParam(defaultValue = "50") int limit,
            @RequestParam(required = false) String q) {
        return queries.applications(Math.min(limit, 500), q);
    }

    @GetMapping("/{appRef}/timeline")
    public java.util.List<java.util.Map<String, Object>> timeline(@PathVariable String appRef) {
        return queries.timeline(appRef);
    }

    @GetMapping("/summary")
    public java.util.Map<String, Object> summary() {
        return queries.summary();
    }

    @GetMapping("/stages")
    public java.util.List<java.util.Map<String, Object>> stages() {
        return queries.stageDefinitions();
    }

    @ExceptionHandler(CreditApplicationNotFoundException.class)
    @ResponseStatus(HttpStatus.NOT_FOUND)
    public ProblemDetail notFound(CreditApplicationNotFoundException e) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, e.getMessage());
    }

    @ExceptionHandler(UnknownStageException.class)
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public ProblemDetail unknownStage(UnknownStageException e) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST, e.getMessage());
    }
}
