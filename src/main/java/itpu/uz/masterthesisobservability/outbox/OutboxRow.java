package itpu.uz.masterthesisobservability.outbox;

import org.springframework.jdbc.core.RowMapper;

import java.util.HexFormat;

public record OutboxRow(long id, String eventIdHex, String aggregateType, String aggregateId,
                        String eventType, long eventSeq, String schemaVersion,
                        String traceId, String payload) {

    public static final RowMapper<OutboxRow> MAPPER = (rs, n) -> new OutboxRow(
            rs.getLong("ID"),
            HexFormat.of().formatHex(rs.getBytes("EVENT_ID")),
            rs.getString("AGGREGATE_TYPE"),
            rs.getString("AGGREGATE_ID"),
            rs.getString("EVENT_TYPE"),
            rs.getLong("EVENT_SEQ"),
            rs.getString("SCHEMA_VERSION"),
            rs.getString("TRACE_ID"),
            rs.getString("PAYLOAD"));
}
