-- Генеративные проверки ограничений схемы.
-- Скрипт создаёт тестовые данные, проверяет свойства в циклах
-- и в конце полностью откатывает транзакцию.

BEGIN;

DO $$
DECLARE
    v_organizer_id INTEGER;
    v_customer_id  INTEGER;
    v_location_id  INTEGER;
    v_event_id     INTEGER;
    v_event_2_id   INTEGER;
    v_order_id     INTEGER;
    v_past_event_rejected BOOLEAN;
    v_test_start   TIMESTAMPTZ := now() + INTERVAL '7 days';
    i              INTEGER;
BEGIN

    ----------------------------------------------------------------------
    -- Базовые допустимые данные
    ----------------------------------------------------------------------

    INSERT INTO users (name, email, role)
    VALUES (
        'Property Test Organizer',
        'property.organizer@example.test',
        'organizer'
    )
    RETURNING user_id INTO v_organizer_id;

    INSERT INTO users (name, email, role)
    VALUES (
        'Property Test Customer',
        'property.customer@example.test',
        'customer'
    )
    RETURNING user_id INTO v_customer_id;

    INSERT INTO locations (name, address, capacity)
    VALUES (
        'Property Test Location',
        'Test address',
        100
    )
    RETURNING location_id INTO v_location_id;

    INSERT INTO events (
        title,
        datetime,
        duration,
        type,
        ticket_price,
        status,
        user_id,
        location_id
    )
    VALUES (
        'Property Test Event',
        v_test_start,
        INTERVAL '2 hours',
        'test',
        100.00,
        'published',
        v_organizer_id,
        v_location_id
    )
    RETURNING event_id INTO v_event_id;


    ----------------------------------------------------------------------
    -- Создаём корректный заказ.
    -- Он нужен для проверки CHECK ограничения цены билета.
    ----------------------------------------------------------------------

    INSERT INTO orders (
        user_id,
        event_id
    )
    VALUES (
        v_customer_id,
        v_event_id
    )
    RETURNING order_id INTO v_order_id;


    ----------------------------------------------------------------------
    -- Свойство:
    -- вместимость площадки всегда должна быть положительной.
    ----------------------------------------------------------------------

  FOR i IN 1..30 LOOP
    BEGIN
        INSERT INTO locations (
            name,
            address,
            capacity
        )
        VALUES (
            'Invalid capacity ' || i,
            'Test address',
            -i
        );

        RAISE EXCEPTION
            'capacity=%: expected CHECK constraint violation, but INSERT succeeded',
            -i;

    EXCEPTION
        WHEN check_violation THEN
            NULL;
    END;
END LOOP;



    ----------------------------------------------------------------------
    -- Свойство:
    -- роль пользователя может быть только из заданного набора.
    ----------------------------------------------------------------------

    FOR i IN 1..30 LOOP
        BEGIN
            INSERT INTO users (
                name,
                email,
                role
            )
            VALUES (
                'Invalid role user ' || i,
                'invalid-role-' || i || '@example.test',
                'invalid_role_' || i
            );

            RAISE EXCEPTION
                'role=invalid_role_%: expected CHECK constraint violation, but INSERT succeeded',
                i;

        EXCEPTION
            WHEN check_violation THEN
                NULL;
        END;
    END LOOP;


    ----------------------------------------------------------------------
    -- Свойство:
    -- email должен быть уникальным.
    ----------------------------------------------------------------------

    FOR i IN 1..30 LOOP
        BEGIN
            INSERT INTO users (
                name,
                email,
                role
            )
            VALUES (
                'Duplicate email user ' || i,
                'property.customer@example.test',
                'customer'
            );

            RAISE EXCEPTION
                'duplicate email: expected UNIQUE constraint violation, but INSERT succeeded';

        EXCEPTION
            WHEN unique_violation THEN
                NULL;
        END;
    END LOOP;


    ----------------------------------------------------------------------
    -- Свойство:
    -- цена мероприятия должна быть положительной.
    ----------------------------------------------------------------------

    FOR i IN 1..30 LOOP
        BEGIN
            INSERT INTO events (
                title,
                datetime,
                duration,
                type,
                ticket_price,
                status,
                user_id,
                location_id
            )
            VALUES (
                'Invalid price event ' || i,
                v_test_start + (i || ' days')::INTERVAL,
                INTERVAL '1 hour',
                'test',
                -i,
                'published',
                v_organizer_id,
                v_location_id
            );

            RAISE EXCEPTION
                'ticket_price=%: expected CHECK constraint violation, but INSERT succeeded',
                -i;

        EXCEPTION
            WHEN check_violation THEN
                NULL;
        END;

        
    ----------------------------------------------------------------------
    -- Свойство:
    -- длительность мероприятия должна быть положительной.
    ----------------------------------------------------------------------

    FOR i IN 1..30 LOOP
        BEGIN
            INSERT INTO events (
                title,
                datetime,
                duration,
                type,
                ticket_price,
                status,
                user_id,
                location_id
            )
            VALUES (
                'Invalid duration event ' || i,
                v_test_start + (i || ' days')::INTERVAL,
                -i * INTERVAL '1 minute',
                'test',
                100.00,
                'published',
                v_organizer_id,
                v_location_id
            );

            RAISE EXCEPTION
                'duration=%: expected CHECK constraint violation, but INSERT succeeded',
                -i;

        EXCEPTION
            WHEN check_violation THEN
                NULL;
        END;
    END LOOP;



    ----------------------------------------------------------------------
    -- Свойство:
    -- статус мероприятия может быть только из разрешённого набора.
    ----------------------------------------------------------------------

    FOR i IN 1..30 LOOP
        BEGIN
            INSERT INTO events (
                title,
                datetime,
                duration,
                type,
                ticket_price,
                status,
                user_id,
                location_id
            )
            VALUES (
                'Invalid status event ' || i,
                v_test_start + (i || ' days')::INTERVAL,
                INTERVAL '1 hour',
                'test',
                100.00,
                'invalid_status_' || i,
                v_organizer_id,
                v_location_id
            );

            RAISE EXCEPTION
                'status=invalid_status_%: expected CHECK constraint violation, but INSERT succeeded',
                i;

        EXCEPTION
            WHEN check_violation THEN
                NULL;
        END;
    END LOOP;



    ----------------------------------------------------------------------
    -- Свойство:
    -- статус билета может быть только из разрешённого набора.
    ----------------------------------------------------------------------

    FOR i IN 1..30 LOOP
        BEGIN
            INSERT INTO tickets (
                price,
                status,
                order_id
            )
            VALUES (
                100.00,
                'invalid_status_' || i,
                v_order_id
            );

            RAISE EXCEPTION
                'ticket status=invalid_status_%: expected CHECK constraint violation, but INSERT succeeded',
                i;

        EXCEPTION
            WHEN check_violation THEN
                NULL;
        END;
    END LOOP;

        
        
    ------------------------------------------------------------------
    -- Свойство:
    -- цена билета должна быть положительной.
    --
    -- Используем существующий order_id, чтобы проверять именно
    -- CHECK ограничения цены, а не FOREIGN KEY.
    ------------------------------------------------------------------

        BEGIN
            INSERT INTO tickets (
                price,
                status,
                order_id
            )
            VALUES (
                -i,
                'valid',
                v_order_id
            );

            RAISE EXCEPTION
                'ticket price=%: expected CHECK constraint violation, but INSERT succeeded',
                -i;

        EXCEPTION
            WHEN check_violation THEN
                NULL;
        END;
    END LOOP;


    ----------------------------------------------------------------------
    -- Свойство:
    -- мероприятие нельзя создать в прошлом.
    ----------------------------------------------------------------------

    FOR i IN 1..10 LOOP
        BEGIN
            INSERT INTO events (
                title,
                datetime,
                duration,
                type,
                ticket_price,
                status,
                user_id,
                location_id
            )
            VALUES (
                'Past event ' || i,
                now() - (i || ' days')::INTERVAL,
                INTERVAL '1 hour',
                'test',
                100.00,
                'published',
                v_organizer_id,
                v_location_id
            );

            RAISE EXCEPTION
                'past datetime: expected trigger exception, but INSERT succeeded';

        EXCEPTION
            WHEN raise_exception THEN
                NULL;
        END;
    END LOOP;


    ----------------------------------------------------------------------
    -- Свойство:
    -- билет не может ссылаться на отсутствующий заказ.
    ----------------------------------------------------------------------

    FOR i IN 1..30 LOOP
        BEGIN
            INSERT INTO tickets (
                price,
                status,
                order_id
            )
            VALUES (
                100.00,
                'valid',
                1000000 + i
            );

            RAISE EXCEPTION
                'order_id=%: expected FOREIGN KEY violation, but INSERT succeeded',
                1000000 + i;

        EXCEPTION
            WHEN foreign_key_violation THEN
                NULL;
        END;
    END LOOP;


    ----------------------------------------------------------------------
    -- Свойство:
    -- два мероприятия не могут иметь пересекающиеся брони
    -- на одной площадке.
    ----------------------------------------------------------------------

    INSERT INTO location_bookings (
        location_id,
        event_id,
        period
    )
    VALUES (
        v_location_id,
        v_event_id,
        tstzrange(
            v_test_start,
            v_test_start + INTERVAL '2 hours',
            '[)'
        )
    );


    INSERT INTO events (
        title,
        datetime,
        duration,
        type,
        ticket_price,
        status,
        user_id,
        location_id
    )
    VALUES (
        'Overlapping booking event',
        v_test_start + INTERVAL '30 minutes',
        INTERVAL '1 hour',
        'test',
        100.00,
        'published',
        v_organizer_id,
        v_location_id
    )
    RETURNING event_id INTO v_event_2_id;


    BEGIN
        INSERT INTO location_bookings (
            location_id,
            event_id,
            period
        )
        VALUES (
            v_location_id,
            v_event_2_id,
            tstzrange(
                v_test_start + INTERVAL '30 minutes',
                v_test_start + INTERVAL '90 minutes',
                '[)'
            )
        );

        RAISE EXCEPTION
            'overlapping booking: expected EXCLUDE constraint violation, but INSERT succeeded';

    EXCEPTION
        WHEN exclusion_violation THEN
            NULL;
    END;


    ----------------------------------------------------------------------
    -- Все проверки успешно завершились.
    ----------------------------------------------------------------------

    RAISE NOTICE 'Property-based schema checks passed';

END;
$$;

ROLLBACK;