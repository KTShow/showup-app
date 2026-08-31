-- Corrects a single mistagged row found while reviewing the Amazon Prime
-- Video merge: The White Lotus is HBO/Max, not Amazon.
update shows
set platform = 'HBO Max'
where id = '82a77a28-49c7-4b21-b5bd-ec9ddcf9269b'
  and title = 'The White Lotus';
