import {
  Box,
  Button,
  Dropdown,
  NoticeBox,
  Section,
} from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useState } from 'react';
import { useBackend } from '../backend';
import { Window } from '../layouts';

type Faction = {
  uid: string;
  name: string;
};

type FactionTaggerData = {
  target_name: string;
  current_uid: string | null;
  current_name: string | null;
  is_admin: BooleanLike;
  own_uid: string | null;
  own_name: string | null;
  factions: Faction[];
  is_cryopod: BooleanLike;
  persistent_spawn: BooleanLike;
  is_telecomms: BooleanLike;
  is_public_comms: BooleanLike;
  is_autodoc: BooleanLike;
  is_public_autodoc: BooleanLike;
  is_lace_storage: BooleanLike;
  is_public_lace: BooleanLike;
  is_airlock: BooleanLike;
  is_public_airlock: BooleanLike;
  is_turret: BooleanLike;
  turret_enabled: BooleanLike;
  turret_lethal: BooleanLike;
  turret_target_mode: string;
  is_public_turret: BooleanLike;
  personal_owner_name: string | null;
  is_own_personal_tag: BooleanLike;
  can_personal_tag: BooleanLike;
  is_crew_tagged: BooleanLike;
  can_crew_tag: BooleanLike;
  can_manage_crew: BooleanLike;
};

const TURRET_MODES: { mode: string; label: string }[] = [
  { mode: 'nonfaction', label: 'Non-Faction' },
  { mode: 'wildlife', label: 'Wildlife Only' },
  { mode: 'both', label: 'Both' },
];

export const FactionTagger = (props) => {
  const { act, data } = useBackend<FactionTaggerData>();
  const {
    target_name,
    current_uid,
    current_name,
    is_admin,
    own_uid,
    factions = [],
    is_cryopod,
    persistent_spawn,
    is_telecomms,
    is_public_comms,
    is_autodoc,
    is_public_autodoc,
    is_lace_storage,
    is_public_lace,
    is_airlock,
    is_public_airlock,
    is_turret,
    turret_enabled,
    turret_lethal,
    turret_target_mode,
    is_public_turret,
    personal_owner_name,
    is_own_personal_tag,
    can_personal_tag,
    is_crew_tagged,
    can_crew_tag,
    can_manage_crew,
  } = data;
  const [selected, setSelected] = useState(current_uid || own_uid || '');

  if (!target_name) {
    return (
      <Window width={380} height={300} title="Faction Tagger">
        <Window.Content>
          <NoticeBox>
            No target selected. Click a compatible machine while holding the
            tagger.
          </NoticeBox>
        </Window.Content>
      </Window>
    );
  }

  return (
    <Window width={380} height={360} title="Faction Tagger">
      <Window.Content scrollable>
        <Section title={target_name}>
          <Box mb={1}>
            Current network:{' '}
            {personal_owner_name ? (
              <Box inline bold color="average">
                Personal ({personal_owner_name})
              </Box>
            ) : is_crew_tagged ? (
              <Box inline bold color="average">
                Crew
              </Box>
            ) : current_uid ? (
              <Box inline bold color="good">
                {current_name}
              </Box>
            ) : (
              <Box inline bold color="average">
                unassigned
              </Box>
            )}
          </Box>
          {factions.length === 0 ? (
            <NoticeBox>
              You have no faction-issued ID -- nothing to tag this to.
            </NoticeBox>
          ) : (
            <Dropdown
              width="100%"
              selected={selected || 'Select a faction...'}
              options={factions.map((f) => f.name)}
              onSelected={(name) => {
                const match = factions.find((f) => f.name === name);
                setSelected(match ? match.uid : '');
              }}
            />
          )}
          <Box mt={1}>
            <Button
              icon="tag"
              color="good"
              disabled={!selected}
              onClick={() => act('set', { uid: selected })}
            >
              Set
            </Button>
            <Button
              icon="times"
              color="bad"
              disabled={!current_uid && !personal_owner_name && !is_crew_tagged}
              onClick={() => act('release')}
            >
              Release
            </Button>
          </Box>
        </Section>
        {!!can_crew_tag && (
          <Section title="Crew Use">
            <Button
              icon="users"
              color="good"
              disabled={!can_manage_crew}
              tooltip="Tag this device to this ship's crew (the owner, plus anyone added via the drydock program's Crew tab). Only the ship's owner (or a faction officer, for faction ships) can set this."
              onClick={() => act('set_crew')}
            >
              Tag to Ship Crew
            </Button>
          </Section>
        )}
        {!!can_personal_tag && (
          <Section title="Personal Use">
            {personal_owner_name && !is_own_personal_tag && !is_admin && (
              <NoticeBox>
                Personally tagged to {personal_owner_name}. Only they or an
                admin can change this.
              </NoticeBox>
            )}
            <Button
              icon="user"
              color="good"
              disabled={!!personal_owner_name && !is_own_personal_tag}
              tooltip="Tag this device to yourself. An untagged device can always be personally tagged; a faction-tagged one needs officer access in that faction."
              onClick={() => act('set_personal')}
            >
              Tag to Me
            </Button>
            {!!is_admin && personal_owner_name && !is_own_personal_tag && (
              <Button
                icon="user-shield"
                color="bad"
                tooltip="Force-tag this device to yourself, bypassing the existing personal tag."
                onClick={() => act('override_personal')}
              >
                Override Tag
              </Button>
            )}
          </Section>
        )}
        {!!(is_admin && is_cryopod) && (
          <Section title="Admin: Public Spawn">
            <Button
              icon={persistent_spawn ? 'times' : 'door-open'}
              color={persistent_spawn ? 'bad' : 'good'}
              onClick={() => act('toggle_public_spawn')}
            >
              {persistent_spawn
                ? 'Clear Public Spawn Point'
                : 'Mark Public Spawn Point'}
            </Button>
          </Section>
        )}
        {!!(is_admin && is_telecomms) && (
          <Section title="Admin: Public Comms">
            <Button
              icon={is_public_comms ? 'times' : 'broadcast-tower'}
              color={is_public_comms ? 'bad' : 'good'}
              onClick={() => act('toggle_public_comms')}
            >
              {is_public_comms ? 'Clear Public Comms' : 'Mark Public Comms'}
            </Button>
          </Section>
        )}
        {!!(is_admin && is_autodoc) && (
          <Section title="Admin: Public Autodoc">
            <Button
              icon={is_public_autodoc ? 'times' : 'medkit'}
              color={is_public_autodoc ? 'bad' : 'good'}
              onClick={() => act('toggle_public_autodoc')}
            >
              {is_public_autodoc ? 'Clear Public Autodoc' : 'Mark Public Autodoc'}
            </Button>
          </Section>
        )}
        {!!(is_admin && is_lace_storage) && (
          <Section title="Admin: Public Lace Vault">
            <Button
              icon={is_public_lace ? 'times' : 'vial'}
              color={is_public_lace ? 'bad' : 'good'}
              onClick={() => act('toggle_public_lace')}
            >
              {is_public_lace ? 'Clear Public Vault' : 'Mark Public Vault'}
            </Button>
          </Section>
        )}
        {!!is_airlock && current_uid && current_uid !== 'public' && (
          <Section title="Door Access">
            <Button
              icon="key"
              onClick={() => act('configure_door_access')}
            >
              Configure Door Access
            </Button>
          </Section>
        )}
        {!!is_turret && current_uid && (
          <Section title="Turret Control">
            <Button
              mb={0.5}
              content={turret_enabled ? 'Enabled' : 'Disabled'}
              color={turret_enabled ? 'good' : 'bad'}
              onClick={() => act('toggle_turret_power')}
            />
            <Button
              mb={0.5}
              content={turret_lethal ? 'Lethal' : 'Stun'}
              color={turret_lethal ? 'bad' : 'good'}
              onClick={() => act('toggle_turret_lethal')}
            />
            {TURRET_MODES.map((m) => (
              <Button
                key={m.mode}
                mb={0.5}
                selected={turret_target_mode === m.mode}
                disabled={current_uid === 'public' && m.mode !== 'wildlife'}
                onClick={() => act('set_turret_mode', { mode: m.mode })}
              >
                {m.label}
              </Button>
            ))}
          </Section>
        )}
        {!!(is_admin && is_turret) && (
          <Section title="Admin: Public Turret">
            <Button
              icon={is_public_turret ? 'times' : 'door-open'}
              color={is_public_turret ? 'bad' : 'good'}
              onClick={() => act('toggle_public_turret')}
            >
              {is_public_turret ? 'Clear Public Turret' : 'Mark Public Turret'}
            </Button>
          </Section>
        )}
        {!!(is_admin && is_airlock) && (
          <Section title="Admin: Public Airlock">
            <Button
              icon={is_public_airlock ? 'times' : 'door-open'}
              color={is_public_airlock ? 'bad' : 'good'}
              onClick={() => act('toggle_public_airlock')}
            >
              {is_public_airlock ? 'Clear Public Airlock' : 'Mark Public Airlock'}
            </Button>
          </Section>
        )}
      </Window.Content>
    </Window>
  );
};
