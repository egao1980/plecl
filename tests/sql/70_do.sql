-- DO (plpython_do)

CREATE TABLE do_t(id integer PRIMARY KEY, n integer);

DO LANGUAGE plecl $plecl$
(plecl:execute "INSERT INTO do_t(id, n) VALUES (1, 99)")
$plecl$;

SELECT plecl_expect((SELECT n FROM do_t WHERE id = 1) = 99, 'DO execute');

DO LANGUAGE pleclu $plecl$
(plecl:execute "UPDATE do_t SET n = 100 WHERE id = 1")
$plecl$;

SELECT plecl_expect((SELECT n FROM do_t WHERE id = 1) = 100, 'DO LANGUAGE pleclu');
