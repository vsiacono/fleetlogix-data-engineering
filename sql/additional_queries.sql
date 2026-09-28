
-- ******************************
-- Query 1: Contar vehículos por tipo
-- Problema de negocio: Conocer la composición de la flota
EXPLAIN ANALYZE
SELECT v.vehicle_type, count (v.vehicle_type)
FROM vehicles v
GROUP BY v.vehicle_type 
ORDER BY count (v.vehicle_type) desc 

-- Query 2: Listar conductores con licencia próxima a vencer (60 días)
-- Problema de negocio: Prevenir problemas legales por licencias vencidas
EXPLAIN ANALYZE
SELECT
    driver_id,
    employee_code,
    first_name || ' ' || last_name AS nombre_completo,
    license_number,
    license_expiry,
    (license_expiry - CURRENT_DATE) AS dias_para_vencer,
    phone,
    status
FROM drivers
WHERE status = 'active'
  AND license_expiry BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '60 days'
ORDER BY license_expiry ASC;

-- Query 3: Total de viajes por estado

-- Problema de negocio: Monitorear operaciones en curso
EXPLAIN ANALYZE
SELECT
    status,
    COUNT(*) AS total_viajes,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS porcentaje
FROM trips
GROUP BY status
ORDER BY total_viajes DESC;

-- Query 4: Total de entregas por ciudad destino en los últimos 2 meses

-- Problema de negocio: Identificar demanda por ciudad para planificación de recursos
EXPLAIN ANALYZE
SELECT
    r.destination_city AS ciudad_destino,
    COUNT(*) AS total_entregas,
    COUNT(*) FILTER (WHERE d.delivery_status = 'delivered') AS entregadas,
    COUNT(*) FILTER (WHERE d.delivery_status != 'delivered') AS pendientes_o_fallidas,
    ROUND(100.0 * COUNT(*) FILTER (WHERE d.delivery_status = 'delivered') / COUNT(*), 2) AS pct_cumplimiento
FROM deliveries d
JOIN trips t ON d.trip_id = t.trip_id
JOIN routes r ON t.route_id = r.route_id
WHERE d.scheduled_datetime >= CURRENT_DATE - INTERVAL '2 months'
GROUP BY r.destination_city
ORDER BY total_entregas DESC;

-- Query 5: Conductores activos con cantidad de viajes completados

-- Problema de negocio: Evaluar carga de trabajo por conductor
EXPLAIN ANALYZE
SELECT
    dr.driver_id,
    dr.employee_code,
    dr.first_name || ' ' || dr.last_name AS conductor,
    COUNT(t.trip_id) FILTER (WHERE t.status = 'completed') AS viajes_completados
FROM drivers dr
LEFT JOIN trips t ON dr.driver_id = t.driver_id
WHERE dr.status = 'active'
GROUP BY dr.driver_id, dr.employee_code, dr.first_name, dr.last_name
ORDER BY viajes_completados ASC;  -- ascendente para detectar los de menor carga

-- Query 6: Promedio de entregas por conductor en los últimos 6 meses

-- Problema de negocio: Medir productividad individual de conductores
EXPLAIN ANALYZE
SELECT
    dr.driver_id,
    dr.employee_code,
    dr.first_name || ' ' || dr.last_name AS conductor,
    COUNT(DISTINCT t.trip_id) AS viajes_realizados,
    COUNT(del.delivery_id) AS entregas_totales,
    ROUND(COUNT(del.delivery_id)::NUMERIC / NULLIF(COUNT(DISTINCT t.trip_id), 0), 2) AS entregas_promedio_por_viaje
FROM drivers dr
JOIN trips t ON dr.driver_id = t.driver_id
JOIN deliveries del ON del.trip_id = t.trip_id
WHERE dr.status = 'active'
  AND t.departure_datetime >= CURRENT_DATE - INTERVAL '6 months'
GROUP BY dr.driver_id, dr.employee_code, dr.first_name, dr.last_name
ORDER BY entregas_promedio_por_viaje DESC;


-- Query 7: Rutas con mayor consumo de combustible por kilómetro

-- Problema de negocio: Identificar rutas ineficientes para optimización
EXPLAIN ANALYZE
SELECT
    r.route_id,
    r.route_code,
    r.origin_city || ' → ' || r.destination_city AS ruta,
    r.distance_km,
    COUNT(t.trip_id) AS viajes_realizados,
    ROUND(AVG(t.fuel_consumed_liters), 2) AS consumo_promedio_litros,
    ROUND(AVG(t.fuel_consumed_liters) / NULLIF(r.distance_km, 0), 4) AS litros_por_km
FROM routes r
JOIN trips t ON r.route_id = t.route_id
WHERE t.fuel_consumed_liters IS NOT NULL
GROUP BY r.route_id, r.route_code, r.origin_city, r.destination_city, r.distance_km
ORDER BY litros_por_km DESC;

-- Query 8: Análisis de entregas retrasadas por día de la semana

-- Problema de negocio: Identificar patrones de retraso para mejorar planificación
EXPLAIN ANALYZE
SELECT
    TO_CHAR(d.scheduled_datetime, 'Day') AS dia_semana,
    EXTRACT(DOW FROM d.scheduled_datetime) AS dia_numero,
    COUNT(*) FILTER (WHERE d.delivered_datetime > d.scheduled_datetime) AS entregas_retrasadas,
    ROUND(AVG(
        EXTRACT(EPOCH FROM (d.delivered_datetime - d.scheduled_datetime)) / 3600
    ) FILTER (WHERE d.delivered_datetime > d.scheduled_datetime), 2) AS horas_promedio_retraso
FROM deliveries d
WHERE d.delivered_datetime IS NOT NULL
GROUP BY TO_CHAR(d.scheduled_datetime, 'Day'), EXTRACT(DOW FROM d.scheduled_datetime)
ORDER BY dia_numero;

-- Avanzadas


-- Query 9: Costo de mantenimiento por kilómetro recorrido

-- Problema de negocio: Evaluar costo-beneficio de cada tipo de vehículo
EXPLAIN ANALYZE
WITH costos AS (
    SELECT vehicle_id, SUM(cost) AS costo_total
    FROM maintenance
    GROUP BY vehicle_id
),
kilometros AS (
    SELECT t.vehicle_id, SUM(r.distance_km) AS km_total
    FROM trips t
    JOIN routes r ON t.route_id = r.route_id
    GROUP BY t.vehicle_id
)
SELECT
    v.vehicle_id,
    v.license_plate,
    v.vehicle_type,
    c.costo_total,
    k.km_total,
    ROUND(c.costo_total / NULLIF(k.km_total, 0), 2) AS costo_por_km
FROM vehicles v
JOIN costos c ON v.vehicle_id = c.vehicle_id
JOIN kilometros k ON v.vehicle_id = k.vehicle_id
ORDER BY costo_por_km DESC
LIMIT 20;

-- Query 10: Ranking de conductores por eficiencia usando Window Functions

-- Problema de negocio: Identificar top performers para incentivos

EXPLAIN ANALYZE
WITH metricas_conductor AS (
    SELECT
        dr.driver_id,
        dr.employee_code,
        dr.first_name || ' ' || dr.last_name AS conductor,
        COUNT(DISTINCT t.trip_id) AS viajes_completados,
        COUNT(del.delivery_id) AS entregas_totales,
        ROUND(AVG(EXTRACT(EPOCH FROM (t.arrival_datetime - t.departure_datetime)) / 3600), 2) AS horas_promedio_viaje,
        ROUND(SUM(t.fuel_consumed_liters) / NULLIF(SUM(r.distance_km), 0), 4) AS litros_por_km,
        COUNT(del.delivery_id) FILTER (WHERE del.delivered_datetime <= del.scheduled_datetime) AS entregas_a_tiempo,
        ROUND(
            100.0 * COUNT(del.delivery_id) FILTER (WHERE del.delivered_datetime <= del.scheduled_datetime)
            / NULLIF(COUNT(del.delivery_id) FILTER (WHERE del.delivered_datetime IS NOT NULL), 0),
            2
        ) AS pct_puntualidad
    FROM drivers dr
    JOIN trips t ON dr.driver_id = t.driver_id
    JOIN routes r ON t.route_id = r.route_id
    LEFT JOIN deliveries del ON del.trip_id = t.trip_id
    WHERE dr.status = 'active'
      AND t.status = 'completed'
    GROUP BY dr.driver_id, dr.employee_code, dr.first_name, dr.last_name
)
SELECT
    driver_id,
    employee_code,
    conductor,
    viajes_completados,
    entregas_totales,
    horas_promedio_viaje,
    litros_por_km,
    pct_puntualidad,
    RANK() OVER (ORDER BY entregas_totales DESC) AS ranking_entregas,
    RANK() OVER (ORDER BY litros_por_km ASC) AS ranking_eficiencia_combustible,
    RANK() OVER (ORDER BY pct_puntualidad DESC) AS ranking_puntualidad
FROM metricas_conductor
ORDER BY ranking_entregas
LIMIT 30;

-- Query 11: Análisis de tendencia de viajes con LAG y LEAD

-- Problema de negocio: Proyectar necesidades futuras basadas en tendencias

EXPLAIN ANALYZE
WITH viajes_por_mes AS (
    SELECT
        DATE_TRUNC('month', departure_datetime) AS mes,
        COUNT(*) AS total_viajes
    FROM trips
    WHERE status = 'completed'
    GROUP BY DATE_TRUNC('month', departure_datetime)
),
con_variacion AS (
    SELECT
        mes,
        total_viajes,
        total_viajes - LAG(total_viajes) OVER (ORDER BY mes) AS variacion
    FROM viajes_por_mes
)
SELECT
    mes,
    total_viajes,
    variacion,
    CASE
        WHEN variacion IS NULL THEN 'Sin dato previo'
        WHEN variacion > 0 THEN 'Crecimiento'
        WHEN variacion < 0 THEN 'Caída'
        ELSE 'Estable'
    END AS tendencia
FROM con_variacion
ORDER BY mes;

-- Query 12: Pivot de entregas por hora y día de la semana

-- Problema de negocio: Optimizar horarios de operación y personal

EXPLAIN ANALYZE
SELECT
    EXTRACT(HOUR FROM scheduled_datetime) AS hora_del_dia,
    COUNT(*) FILTER (WHERE EXTRACT(DOW FROM scheduled_datetime) = 0) AS domingo,
    COUNT(*) FILTER (WHERE EXTRACT(DOW FROM scheduled_datetime) = 1) AS lunes,
    COUNT(*) FILTER (WHERE EXTRACT(DOW FROM scheduled_datetime) = 2) AS martes,
    COUNT(*) FILTER (WHERE EXTRACT(DOW FROM scheduled_datetime) = 3) AS miercoles,
    COUNT(*) FILTER (WHERE EXTRACT(DOW FROM scheduled_datetime) = 4) AS jueves,
    COUNT(*) FILTER (WHERE EXTRACT(DOW FROM scheduled_datetime) = 5) AS viernes,
    COUNT(*) FILTER (WHERE EXTRACT(DOW FROM scheduled_datetime) = 6) AS sabado,
    COUNT(*) AS total_hora
FROM deliveries
GROUP BY EXTRACT(HOUR FROM scheduled_datetime)
ORDER BY hora_del_dia;


CREATE INDEX idx_trips_composite_joins ON trips(vehicle_id, driver_id, route_id, departure_datetime)
WHERE status = 'completed';

CREATE INDEX idx_deliveries_scheduled_datetime ON deliveries(scheduled_datetime, delivery_status)
WHERE delivery_status = 'delivered';

CREATE INDEX idx_maintenance_vehicle_cost ON maintenance(vehicle_id, cost);

CREATE INDEX idx_drivers_status_license ON drivers(status, license_expiry)
WHERE status = 'active';

CREATE INDEX idx_routes_metrics ON routes(route_id, distance_km, destination_city);

SELECT 
    schemaname,
    tablename,
    indexname,
    indexdef
FROM pg_indexes
WHERE schemaname = 'public'
    AND indexname LIKE 'idx_%'
ORDER BY tablename, indexname;

ANALYZE vehicles;
ANALYZE drivers;
ANALYZE routes;
ANALYZE trips;
ANALYZE deliveries;
ANALYZE maintenance;
