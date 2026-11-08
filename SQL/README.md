# BS19 manual database install preview

`bs19-manual-install.sql` combines the SQL migrations shipped in the current public BS19 repository, in the order used by `bs_core`. It includes the crafting tables and records each migration in `bs_migrations` so startup does not try to apply it again.

Use this file only for a new installation with an empty database. Create and select a UTF-8 database in MariaDB/MySQL, import the file once, then set the connection string and start the server. If an import stops partway through, use a fresh empty database and import again; do not rerun it over partial tables.

Existing installations should not import this file. Back up the database and let `bs_core` apply only missing migrations on startup. When files have been customized, review the release changes before updating them.

This file matches the SQL migrations in this release. For a later release, use that release's installer.
