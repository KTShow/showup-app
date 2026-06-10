// ============================================================
// SHOWUP — supabase.js
// All database and auth operations live here.
// index.html imports this file and calls these functions.
// ============================================================

import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';

const SUPABASE_URL = 'https://sgnulweruogjfdddwboe.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNnbnVsd2VydW9namZkZGR3Ym9lIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkxMzQ0MzMsImV4cCI6MjA5NDcxMDQzM30.bL28eAEx24TjpE8msSmoZHUQOWU5Yj6EfHpMv8V5VrM';

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
    flowType: 'implicit',
  }
});

// ============================================================
// AUTH
// ============================================================

// Send magic link to email
export async function sendMagicLink(email) {
  const { error } = await supabase.auth.signInWithOtp({
    email,
    options: {
      emailRedirectTo: window.location.origin,
    }
  });
  if (error) throw error;
}

// Sign out
export async function signOut() {
  const { error } = await supabase.auth.signOut();
  if (error) throw error;
}

// Get current session (returns null if not logged in)
export async function getSession() {
  const { data: { session } } = await supabase.auth.getSession();
  return session;
}

// Listen for auth state changes (login, logout, token refresh)
export function onAuthStateChange(callback) {
  return supabase.auth.onAuthStateChange((_event, session) => {
    callback(session);
  });
}

// ============================================================
// USER PROFILE
// ============================================================

// Generate a username from first name and last initial
// e.g. "Tracey" + "M" -> "tracey-m" with collision suffix if needed
export function generateUsername(firstName, lastInitial) {
  const base = [firstName, lastInitial]
    .filter(Boolean)
    .join('-')
    .toLowerCase()
    .replace(/[^a-z0-9-]/g, '');
  const suffix = Math.random().toString(36).slice(2, 6);
  return `${base}-${suffix}`;
}

// Check if a user profile exists for the current auth user
export async function getUserProfile() {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return null;

  const { data, error } = await supabase
    .from('users')
    .select('*')
    .eq('id', user.id)
    .single();

  if (error && error.code === 'PGRST116') return null; // no row found
  if (error) throw error;
  return data;
}

// Create a new user profile after onboarding
export async function createUserProfile(profileData) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error('Not authenticated');

  const username = generateUsername(profileData.firstName, profileData.lastInitial);

  const { data, error } = await supabase
    .from('users')
    .insert({
      id: user.id,
      email: user.email,
      username,
      first_name: profileData.firstName,
      last_initial: profileData.lastInitial,
      city: profileData.city,
      state: profileData.state,
      age_range: profileData.ageRange,
      gender: profileData.gender,
      room: 'tuscany',
      session_count: 1,
      last_active: new Date().toISOString(),
    })
    .select()
    .single();

  if (error) throw error;

  // Create their Living Room
  await supabase.from('living_rooms').insert({
    owner_id: user.id,
    name: `${profileData.firstName}'s Living Room`,
    is_public: false,
  });

  // Record session
  await recordSession();

  return data;
}

// Save psychographic data from Tell Us More screen
export async function saveTellMoreData(psychData) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error('Not authenticated');

  const { error } = await supabase
    .from('users')
    .update({
      career: psychData.career,
      hobbies: psychData.hobbies,
      household: psychData.household,
      watch_when: psychData.watchWhen,
      watch_freq: psychData.watchFreq,
      discovery: psychData.discovery,
    })
    .eq('id', user.id);

  if (error) throw error;
}

// Update basic profile (name, city, state, age, gender)
export async function updateUserProfile(profileData) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error('Not authenticated');

  const { data, error } = await supabase
    .from('users')
    .update({
      first_name: profileData.firstName,
      last_initial: profileData.lastInitial,
      city: profileData.city,
      state: profileData.state,
      age_range: profileData.ageRange,
      gender: profileData.gender,
      room: profileData.room,
      last_active: new Date().toISOString(),
    })
    .eq('id', user.id)
    .select()
    .single();

  if (error) throw error;
  return data;
}

// Update room theme only
export async function updateRoom(roomKey) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error('Not authenticated');

  const { error } = await supabase
    .from('users')
    .update({ room: roomKey })
    .eq('id', user.id);

  if (error) throw error;
}

// Record a new session (called on every login)
export async function recordSession() {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return;

  await supabase.from('sessions').insert({
    user_id: user.id,
    device_hint: navigator.userAgent.slice(0, 200),
  });

  // Increment session count
  await supabase.rpc('increment_session_count', { uid: user.id })
    .then(() => {}) // best effort, don't throw
    .catch(() => {});
}

// Delete all user data (GDPR / user request)
export async function deleteUserData() {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error('Not authenticated');

  // Cascade deletes handle related records via foreign keys
  const { error } = await supabase
    .from('users')
    .delete()
    .eq('id', user.id);

  if (error) throw error;

  await supabase.auth.signOut();
}

// ============================================================
// SHOWS
// ============================================================

// Load all shows for the current user
export async function loadShows() {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error('Not authenticated');

  const { data, error } = await supabase
    .from('shows')
    .select(`
      *,
      reactions(*)
    `)
    .eq('user_id', user.id)
    .order('added_at', { ascending: false });

  if (error) throw error;
  return data || [];
}

// Add a new show
export async function addShow(showData) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error('Not authenticated');

  const { data, error } = await supabase
    .from('shows')
    .insert({
      user_id: user.id,
      title: showData.title,
      platform: showData.platform,
      status: showData.status,
      source: showData.source || 'manual',
      influenced_by: showData.influencedBy || null,
    })
    .select()
    .single();

  if (error) throw error;
  return data;
}

// Update a show's status (e.g. watching -> watched, mark DNF)
export async function updateShowStatus(showId, status, extraFields = {}) {
  const { error } = await supabase
    .from('shows')
    .update({ status, ...extraFields })
    .eq('id', showId);

  if (error) throw error;
}

// Update a show's rating
export async function updateShowRating(showId, rating) {
  const { error } = await supabase
    .from('shows')
    .update({ rating })
    .eq('id', showId);

  if (error) throw error;
}

// Toggle hidden from friends
export async function toggleShowHidden(showId, hidden) {
  const { error } = await supabase
    .from('shows')
    .update({ hidden })
    .eq('id', showId);

  if (error) throw error;
}

// Remove a show
export async function removeShow(showId) {
  const { error } = await supabase
    .from('shows')
    .delete()
    .eq('id', showId);

  if (error) throw error;
}

// ============================================================
// REACTIONS
// ============================================================

export async function addReaction(showId, text, sentiment) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error('Not authenticated');

  const { data, error } = await supabase
    .from('reactions')
    .insert({
      show_id: showId,
      user_id: user.id,
      text,
      sentiment,
    })
    .select()
    .single();

  if (error) throw error;
  return data;
}

// ============================================================
// TOP 5 SHOWS
// ============================================================

export async function loadTop5() {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error('Not authenticated');

  const { data, error } = await supabase
    .from('top5_shows')
    .select('*')
    .eq('user_id', user.id)
    .order('rank', { ascending: true });

  if (error) throw error;
  return data || [];
}

export async function saveTop5(showsArray) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error('Not authenticated');

  // Delete existing and re-insert in rank order
  await supabase.from('top5_shows').delete().eq('user_id', user.id);

  if (!showsArray.length) return;

  const rows = showsArray.map((s, i) => ({
    user_id: user.id,
    title: s.title,
    platform: s.platform || '',
    rank: i + 1,
  }));

  const { error } = await supabase.from('top5_shows').insert(rows);
  if (error) throw error;
}

// ============================================================
// LIVING ROOM / FRIENDS
// ============================================================

// Get the current user's Living Room
export async function getMyLivingRoom() {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error('Not authenticated');

  const { data, error } = await supabase
    .from('living_rooms')
    .select('*')
    .eq('owner_id', user.id)
    .single();

  if (error && error.code === 'PGRST116') return null;
  if (error) throw error;
  return data;
}

// Get active friends in the user's Living Room with their shows
export async function getFriendsWithShows() {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error('Not authenticated');

  // Get user's living room
  const room = await getMyLivingRoom();
  if (!room) return [];

  // Get active members
  const { data: members, error: membersError } = await supabase
    .from('living_room_members')
    .select(`
      user_id,
      users(id, first_name, last_initial, city, state, room, is_public, account_type)
    `)
    .eq('living_room_id', room.id)
    .eq('status', 'active')
    .neq('user_id', user.id);

  if (membersError) throw membersError;
  if (!members || !members.length) return [];

  const friendIds = members.map(m => m.user_id);

  // Get their shows (non-hidden only)
  const { data: shows, error: showsError } = await supabase
    .from('shows')
    .select(`*, reactions(*)`)
    .in('user_id', friendIds)
    .eq('hidden', false);

  if (showsError) throw showsError;

  // Get their top5
  const { data: top5, error: top5Error } = await supabase
    .from('top5_shows')
    .select('*')
    .in('user_id', friendIds)
    .order('rank', { ascending: true });

  if (top5Error) throw top5Error;

  // Assemble friend objects
  return members.map(m => {
    const u = m.users;
    const friendShows = (shows || []).filter(s => s.user_id === u.id);
    const friendTop5 = (top5 || []).filter(t => t.user_id === u.id);
    return {
      id: u.id,
      name: `${u.first_name} ${u.last_initial}.`,
      city: [u.city, u.state].filter(Boolean).join(', '),
      room: u.room || 'tuscany',
      top5: friendTop5.map(t => ({ title: t.title, platform: t.platform })),
      watching: friendShows.filter(s => s.status === 'watching'),
      watchlist: friendShows.filter(s => s.status === 'watchlist'),
      watched: friendShows.filter(s => s.status === 'watched' || s.status === 'dnf'),
    };
  });
}

// Process an invite link — creates a pending member record
export async function processInvite(inviterUsername) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error('Not authenticated');

  // Find inviter by username
  const { data: inviter, error: inviterError } = await supabase
    .from('users')
    .select('id')
    .eq('username', inviterUsername)
    .single();

  if (inviterError || !inviter) throw new Error('Invite link not found');

  // Find their living room
  const { data: room, error: roomError } = await supabase
    .from('living_rooms')
    .select('id')
    .eq('owner_id', inviter.id)
    .single();

  if (roomError || !room) throw new Error('Living room not found');

  // Check if already a member
  const { data: existing } = await supabase
    .from('living_room_members')
    .select('id, status')
    .eq('living_room_id', room.id)
    .eq('user_id', user.id)
    .single();

  if (existing && existing.status === 'active') return { status: 'already_active' };
  if (existing && existing.status === 'pending') return { status: 'already_pending' };

  // Create pending membership
  const { error } = await supabase
    .from('living_room_members')
    .insert({
      living_room_id: room.id,
      user_id: user.id,
      invited_by: inviter.id,
      status: 'pending',
    });

  if (error) throw error;
  return { status: 'pending_created' };
}

// Accept a pending invite (called by room owner)
export async function acceptInvite(memberId) {
  const { error } = await supabase
    .from('living_room_members')
    .update({ status: 'active', accepted_at: new Date().toISOString() })
    .eq('id', memberId);

  if (error) throw error;
}

// Get pending invites for the current user's room
export async function getPendingInvites() {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error('Not authenticated');

  const room = await getMyLivingRoom();
  if (!room) return [];

  const { data, error } = await supabase
    .from('living_room_members')
    .select(`
      id,
      invited_at,
      users(first_name, last_initial, city)
    `)
    .eq('living_room_id', room.id)
    .eq('status', 'pending');

  if (error) throw error;
  return data || [];
}

// ============================================================
// REAL-TIME SUBSCRIPTIONS
// ============================================================

// Subscribe to changes in a friend's shows (for live updates in Living Room)
export function subscribeToFriendShows(friendIds, callback) {
  return supabase
    .channel('friend-shows')
    .on('postgres_changes', {
      event: '*',
      schema: 'public',
      table: 'shows',
      filter: `user_id=in.(${friendIds.join(',')})`,
    }, callback)
    .subscribe();
}

// Subscribe to incoming invites for the current user's room
export function subscribeToPendingInvites(livingRoomId, callback) {
  return supabase
    .channel('pending-invites')
    .on('postgres_changes', {
      event: 'INSERT',
      schema: 'public',
      table: 'living_room_members',
      filter: `living_room_id=eq.${livingRoomId}`,
    }, callback)
    .subscribe();
}

// Unsubscribe from a channel
export function unsubscribe(channel) {
  if (channel) supabase.removeChannel(channel);
}

// ============================================================
// HELPER — increment_session_count RPC
// Run this SQL in Supabase to create the function:
//
// create or replace function increment_session_count(uid uuid)
// returns void as $$
//   update users set session_count = session_count + 1,
//   last_active = now() where id = uid;
// $$ language sql security definer;
// ============================================================
