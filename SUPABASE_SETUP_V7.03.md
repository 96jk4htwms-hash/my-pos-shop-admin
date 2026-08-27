# SmartPOS V7.03 Supabase Setup
1. Create the first user in Supabase Authentication > Users. This user is the owner identity.
2. Run SMARTPOS_SUPABASE_FULL_INSTALL_V7.03.sql in Supabase SQL Editor as project owner/postgres.
3. No owners table is required.
4. Buckets created: product-images (public read), documents (private).
5. Storage paths should start with the authenticated user's UUID.
6. Never expose a service_role key in the web app or GitHub.
7. Keep store data and secrets out of the public repository.
