import { Box, Button, LabeledList, NoticeBox, Section, Table } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useBackend } from '../backend';
import { NtosWindow } from '../layouts';

type Occupant = {
  ref: string;
  name: string;
  imprisoned: BooleanLike;
  indefinite: BooleanLike;
  remaining_seconds: number;
};

type PrisonPodData = {
  occupants: Occupant[];
  nopower: BooleanLike;
  broken: BooleanLike;
  faction_name: string | null;
  can_imprison: BooleanLike;
  frozen: BooleanLike;
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

export const PrisonPod = (props) => {
  const { act, data } = useBackend<PrisonPodData>();
  const {
    occupants = [],
    nopower,
    broken,
    faction_name,
    can_imprison,
    frozen,
  } = data;

  return (
    <NtosWindow width={460} height={420}>
      <NtosWindow.Content scrollable>
        {!!broken && <NoticeBox danger>This unit is damaged.</NoticeBox>}
        {!!nopower && <NoticeBox danger>This unit has no power.</NoticeBox>}
        <LabeledList>
          <LabeledList.Item label="Faction">
            {faction_name ?? 'Unassigned'}
          </LabeledList.Item>
          <LabeledList.Item label="Cell Status">
            <Box color={frozen ? 'bad' : 'good'} inline mr={1}>
              {frozen ? 'Frozen' : 'Thawed'}
            </Box>
            <Button
              icon={frozen ? 'sun' : 'snowflake'}
              tooltip={
                frozen
                  ? 'Thaw -- tied prisoner(s) may spawn/play despite their sentence, which keeps ticking regardless.'
                  : 'Freeze -- blocks Play, and immediately returns anyone currently thawed and playing here to the character menu.'
              }
              onClick={() => act('toggle_freeze')}
            >
              {frozen ? 'Thaw' : 'Freeze'}
            </Button>
          </LabeledList.Item>
        </LabeledList>
        <Section title={`Occupants (${occupants.length})`} mt={1}>
          {occupants.length ? (
            <Table>
              <Table.Row header>
                <Table.Cell>Name</Table.Cell>
                <Table.Cell>Sentence</Table.Cell>
                <Table.Cell />
              </Table.Row>
              {occupants.map((occupant) => (
                <Table.Row key={occupant.ref}>
                  <Table.Cell>{occupant.name}</Table.Cell>
                  <Table.Cell>
                    {occupant.imprisoned
                      ? occupant.indefinite
                        ? 'Indefinite'
                        : formatRemaining(occupant.remaining_seconds)
                      : 'Not imprisoned'}
                  </Table.Cell>
                  <Table.Cell collapsing>
                    {!occupant.imprisoned ? (
                      <Button
                        icon="lock"
                        color="bad"
                        disabled={!can_imprison}
                        tooltip={
                          !can_imprison
                            ? 'Must be tagged to a faction before it can imprison anyone.'
                            : 'Imprison this occupant'
                        }
                        onClick={() =>
                          act('imprison', { occupant_ref: occupant.ref })
                        }
                      >
                        Imprison
                      </Button>
                    ) : (
                      <Button
                        icon="door-open"
                        color="good"
                        onClick={() =>
                          act('release', { occupant_ref: occupant.ref })
                        }
                      >
                        Release
                      </Button>
                    )}
                  </Table.Cell>
                </Table.Row>
              ))}
            </Table>
          ) : (
            <Box color="label">Empty.</Box>
          )}
        </Section>
      </NtosWindow.Content>
    </NtosWindow>
  );
};
