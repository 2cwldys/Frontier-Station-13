import { Box, Button, Section, Stack } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useBackend } from '../backend';
import { Window } from '../layouts';

type Character = {
  name: string;
};

type PersistentMenuData = {
  characters: Character[];
  slot_limit: number;
  can_create: BooleanLike;
  persistence_ready: BooleanLike;
  enter_allowed: BooleanLike;
};

export const PersistentMenu = (props) => {
  const { act, data } = useBackend<PersistentMenuData>();
  const {
    characters = [],
    slot_limit = 1,
    persistence_ready,
    enter_allowed,
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
                    disabled={!persistence_ready || !enter_allowed}
                    tooltip={
                      !enter_allowed
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
                    tooltip="Permanently delete this character and free the slot"
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
                tooltip="Create and configure a new character"
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
