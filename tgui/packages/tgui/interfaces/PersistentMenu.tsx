import { Box, Button, Section, Stack } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useBackend } from '../backend';
import { Window } from '../layouts';

type Character = {
  name: string;
  imprisoned: BooleanLike;
  indefinite: BooleanLike;
  remaining_seconds: number;
};

type PersistentMenuData = {
  characters: Character[];
  slot_limit: number;
  can_create: BooleanLike;
  any_imprisoned: BooleanLike;
  persistence_ready: BooleanLike;
  enter_allowed: BooleanLike;
  save_in_progress: BooleanLike;
  whitelisted: BooleanLike;
  central_reachable: BooleanLike;
};

const formatRemaining = (seconds: number) => {
  const total = Math.max(0, Math.floor(seconds));
  const hours = Math.floor(total / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  if (hours > 0) {
    return `${hours}h ${minutes}m`;
  }
  return `${minutes}m`;
};

export const PersistentMenu = (props) => {
  const { act, data } = useBackend<PersistentMenuData>();
  const {
    characters = [],
    slot_limit = 1,
    any_imprisoned,
    persistence_ready,
    enter_allowed,
    save_in_progress,
    whitelisted,
    central_reachable,
  } = data;

  const emptySlots = Math.max(0, slot_limit - characters.length);

  return (
    <Window title="Character Select" width={420} height={520}>
      <Window.Content className="PersistentMenu">
        {characters.map((char) => (
          <Section
            key={char.name}
            title={char.name}
            buttons={
              <Stack>
                <Stack.Item>
                  <Button
                    icon="play"
                    color="green"
                    disabled={
                      !!char.imprisoned ||
                      !persistence_ready ||
                      !enter_allowed ||
                      !!save_in_progress ||
                      !whitelisted ||
                      !central_reachable
                    }
                    tooltip={
                      char.imprisoned
                        ? char.indefinite
                          ? 'This character is imprisoned indefinitely.'
                          : `This character is imprisoned, time left: ${formatRemaining(char.remaining_seconds)}`
                        : !central_reachable
                          ? 'The shared character database is unreachable -- try again shortly.'
                          : save_in_progress
                            ? 'Cannot join server while a save is in progress.'
                            : !whitelisted
                              ? 'You are not whitelisted to join this server.'
                              : !enter_allowed
                                ? 'Joining is currently disabled by an administrator.'
                                : 'Enter the world as this character'
                    }
                    onClick={() => act('play', { name: char.name })}
                  >
                    Play
                  </Button>
                </Stack.Item>
                <Stack.Item>
                  <Button
                    icon="trash"
                    color="red"
                    disabled={!!char.imprisoned}
                    tooltip={
                      char.imprisoned
                        ? 'You are imprisoned.'
                        : 'Permanently delete this character and free the slot'
                    }
                    onClick={() => act('delete_char', { name: char.name })}
                  >
                    Delete
                  </Button>
                </Stack.Item>
              </Stack>
            }
          >
            <Box color="label" fontSize="0.85em">
              Preferences are locked.
            </Box>
          </Section>
        ))}

        {Array.from({ length: emptySlots }, (_, i) => (
          <Section
            key={`empty-${i}`}
            title="Available Slot"
            buttons={
              <Button
                icon="user-plus"
                disabled={!!any_imprisoned}
                tooltip={
                  any_imprisoned
                    ? 'You are imprisoned.'
                    : 'Create and configure a new character'
                }
                onClick={() => act('create')}
              >
                Create Character
              </Button>
            }
          >
            <Box color="label" fontSize="0.85em">
              No character in this slot.
            </Box>
          </Section>
        ))}

      </Window.Content>
    </Window>
  );
};
