package itpu.uz.masterthesisobservability.api;

import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import itpu.uz.masterthesisobservability.config.ObservabilityProperties;
import itpu.uz.masterthesisobservability.service.A1TransactionService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/a1")
@RequiredArgsConstructor
public class A1Controller {

    private final A1TransactionService service;
    private final MeterRegistry meters;
    private final ObservabilityProperties properties;

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public A1TransactionView initiate(@Valid @RequestBody InitiateA1Request request) {
        return timed("initiate", () -> service.initiate(request));
    }

    @PostMapping("/{txnRef}/validate")
    public A1TransactionView validate(@PathVariable String txnRef) {
        return timed("validate", () -> service.validate(txnRef));
    }

    @PostMapping("/{txnRef}/process")
    public A1TransactionView process(@PathVariable String txnRef) {
        return timed("process", () -> service.process(txnRef));
    }

    @PostMapping("/{txnRef}/reject")
    public A1TransactionView reject(@PathVariable String txnRef,
                                    @RequestParam(defaultValue = "AM01") String reasonCode) {
        return timed("reject", () -> service.reject(txnRef, reasonCode));
    }

    @GetMapping("/{txnRef}")
    public A1TransactionView find(@PathVariable String txnRef) {
        return service.find(txnRef);
    }

    /**
     * Per-transition timer tagged with the active mode, so a single Prometheus query yields
     * the OLTP latency comparison across modes without post-processing.
     */
    private A1TransactionView timed(String transition, java.util.function.Supplier<A1TransactionView> op) {
        return Timer.builder("a1.transition")
                .tag("transition", transition)
                .tag("mode", properties.mode().name())
                .register(meters)
                .record(op);
    }
}
