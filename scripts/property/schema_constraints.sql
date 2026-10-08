-- Генеративные проверки ограничений текущей PostgreSQL-схемы.
-- Для каждого свойства проверяется множество недопустимых значений.
-- Все тестовые данные откатываются в конце транзакции.

BEGIN;

DO $$
DECLARE
    v_organizer_id INTEGER;
    v_customer_id  INTEGER;
    v_location_id  INTEGER;
    v_event_id     INTEGER;
    v_order_id     INTEGER;
    i              INTEGER;
BEGIN
    ----------------------------------------------------------------------
    -- Базовые корректные данные
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
        now() + INTERVAL '7 days',
        INTERVAL '2 hours',
        'other',
        100.00,
        'published',
        v_organizer_id,
        v_location_id
    )
    RETURNING event_id INTO v_event_id;

    INSERT INTO orders (
        user_id,
        event_id,
        status,
        total_price
    )
    VALUES (
        v_customer_id,
        v_event_id,
        'paid',
        100.00
    )
    RETURNING order_id INTO v_order_id;


    ----------------------------------------------------------------------
    -- 1. Вместимость площадки должна быть положительной
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
                'capacity=%: expected CHECK violation',
                -i;

        EXCEPTION
            WHEN check_violation THEN
                NULL;
        END;
    END LOOP;


    ----------------------------------------------------------------------
    -- 2. Роль пользователя должна быть из разрешённого набора
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
                'role=invalid_role_%: expected CHECK violation',
                i;

        EXCEPTION
            WHEN check_violation THEN
                NULL;
        END;
    END LOOP;


    ----------------------------------------------------------------------
    -- 3. Email пользователя должен быть уникальным
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
                'duplicate email: expected UNIQUE violation';

        EXCEPTION
            WHEN unique_violation THEN
                NULL;
        END;
    END LOOP;


    ----------------------------------------------------------------------
    -- 4. Тип мероприятия должен быть из разрешённого набора
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
                'Invalid type event ' || i,
                now() + (i || ' days')::INTERVAL,
                INTERVAL '1 hour',
                'invalid_type_' || i,
                100.00,
                'published',
                v_organizer_id,
                v_location_id
            );

            RAISE EXCEPTION
                'type=invalid_type_%: expected CHECK violation',
                i;

        EXCEPTION
            WHEN check_violation THEN
                NULL;
        END;
    END LOOP;


    ----------------------------------------------------------------------
    -- 5. Цена мероприятия должна быть положительной
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
                now() + (i || ' days')::INTERVAL,
                INTERVAL '1 hour',
                'other',
                -i,
                'published',
                v_organizer_id,
                v_location_id
            );

            RAISE EXCEPTION
                'ticket_price=%: expected CHECK violation',
                -i;

        EXCEPTION
            WHEN check_violation THEN
                NULL;
        END;
    END LOOP;


    ----------------------------------------------------------------------
    -- 6. Длительность мероприятия должна быть положительной
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
                now() + (i || ' days')::INTERVAL,
                -i * INTERVAL '1 minute',
                'other',
                100.00,
                'published',
                v_organizer_id,
                v_location_id
            );

            RAISE EXCEPTION
                'duration=%: expected CHECK violation',
                -i;

        EXCEPTION
            WHEN check_violation THEN
                NULL;
        END;
    END LOOP;


    ----------------------------------------------------------------------
    -- 7. Статус мероприятия должен быть из разрешённого набора
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
                now() + (i || ' days')::INTERVAL,
                INTERVAL '1 hour',
                'other',
                100.00,
                'invalid_status_' || i,
                v_organizer_id,
                v_location_id
            );

            RAISE EXCEPTION
                'status=invalid_status_%: expected CHECK violation',
                i;

        EXCEPTION
            WHEN check_violation THEN
                NULL;
        END;
    END LOOP;


    ----------------------------------------------------------------------
    -- 8. Статус заказа должен быть из разрешённого набора
    ----------------------------------------------------------------------

    FOR i IN 1..30 LOOP
        BEGIN
            INSERT INTO orders (
                user_id,
                event_id,
                status,
                total_price
            )
            VALUES (
                v_customer_id,
                v_event_id,
                'invalid_status_' || i,
                100.00
            );

            RAISE EXCEPTION
                'order status=invalid_status_%: expected CHECK violation',
                i;

        EXCEPTION
            WHEN check_violation THEN
                NULL;
        END;
    END LOOP;


    ----------------------------------------------------------------------
    -- 9. Общая стоимость заказа не может быть отрицательной
    ----------------------------------------------------------------------

    FOR i IN 1..30 LOOP
        BEGIN
            INSERT INTO orders (
                user_id,
                event_id,
                status,
                total_price
            )
            VALUES (
                v_customer_id,
                v_event_id,
                'pending',
                -i
            );

            RAISE EXCEPTION
                'total_price=%: expected CHECK violation',
                -i;

        EXCEPTION
            WHEN check_violation THEN
                NULL;
        END;
    END LOOP;


    ----------------------------------------------------------------------
    -- 10. Цена билета должна быть положительной
    ----------------------------------------------------------------------

    FOR i IN 1..30 LOOP
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
                'ticket price=%: expected CHECK violation',
                -i;

        EXCEPTION
            WHEN check_violation THEN
                NULL;
        END;
    END LOOP;


    ----------------------------------------------------------------------
    -- 11. Статус билета должен быть из разрешённого набора
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
                'ticket status=invalid_status_%: expected CHECK violation',
                i;

        EXCEPTION
            WHEN check_violation THEN
                NULL;
        END;
    END LOOP;


    ----------------------------------------------------------------------
    -- 12. Билет не может ссылаться на отсутствующий заказ
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
                'order_id=%: expected FOREIGN KEY violation',
                1000000 + i;

        EXCEPTION
            WHEN foreign_key_violation THEN
                NULL;
        END;
    END LOOP;


    ----------------------------------------------------------------------
    -- 13. Время окончания бронирования должно быть позже начала
    ----------------------------------------------------------------------

    FOR i IN 1..30 LOOP
        BEGIN
            INSERT INTO location_bookings (
                location_id,
                event_id,
                start_time,
                end_time
            )
            VALUES (
                v_location_id,
                v_event_id,
                now() + INTERVAL '10 days',
                now() + INTERVAL '9 days'
            );

            RAISE EXCEPTION
                'invalid booking interval: expected CHECK violation';

        EXCEPTION
            WHEN check_violation THEN
                NULL;
        END;
    END LOOP;


        ----------------------------------------------------------------------
    -- 14. Один event может иметь только одну запись бронирования
    ----------------------------------------------------------------------

    INSERT INTO location_bookings (
        location_id,
        event_id,
        start_time,
        end_time
    )
    VALUES (
        v_location_id,
        v_event_id,
        now() + INTERVAL '20 days',
        now() + INTERVAL '20 days' + INTERVAL '2 hours'
    );

    FOR i IN 1..30 LOOP
        BEGIN
            INSERT INTO location_bookings (
                location_id,
                event_id,
                start_time,
                end_time
            )
            VALUES (
                v_location_id,
                v_event_id,
                now() + (20 + i) * INTERVAL '1 day',
                now() + (20 + i) * INTERVAL '1 day'
                    + INTERVAL '1 hour'
            );

            RAISE EXCEPTION
                'event_id=%: expected UNIQUE violation',
                v_event_id;

        EXCEPTION
            WHEN unique_violation THEN
                NULL;
        END;
    END LOOP;


    ----------------------------------------------------------------------
    -- Все проверки успешно завершились
    ----------------------------------------------------------------------

    RAISE NOTICE 'Property-based schema checks passed';

END;
$$;

ROLLBACK;