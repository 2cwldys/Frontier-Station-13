import { useState } from 'react';
import { Box, Button, Dropdown, NoticeBox, Section, Table } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useBackend } from '../backend';
import { NtosWindow } from '../layouts';

type Prisoner = {
  ckey: string;
  char_name: string;
  indefinite: BooleanLike;
  remaining_seconds: number;
  frozen: BooleanLike;
  cell_ref: string;
};

type Cell = {
  ref: string;
  label: string;
};

type PrisonManagementData = {
  faction_uid: string | null;
  faction_name: string | null;
  prisoners: Prisoner[];
  cells: Cell[];
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

type PrisonerRowProps = {
  prisoner: Prisoner;
  cells: Cell[];
};

const PrisonerRow = (props: PrisonerRowProps) => {
  const { act } = useBackend<PrisonManagementData>();
  const { prisoner: p, cells } = props;

  // Every OTHER faction cell -- transferring someone to the cell they're
  // already in is a no-op the server also refuses, so it's left out of the
  // picker entirely rather than offered and rejected.
  const otherCells = cells.filter((c) => c.ref !== p.cell_ref);
  const [selectedRef, setSelectedRef] = useState<string>(
    otherCells[0]?.ref ?? '',
  );

  return (
    <Table.Row>
      <Table.Cell bold>{p.char_name}</Table.Cell>
      <Table.Cell>
        {p.indefinite ? 'Indefinite' : formatRemaining(p.remaining_seconds)}
      </Table.Cell>
      <Table.Cell color={p.frozen ? 'bad' : 'good'}>
        {p.frozen ? 'Frozen' : 'Thawed'}
      </Table.Cell>
      <Table.Cell>
        <Button
          compact
          icon={p.frozen ? 'sun' : 'snowflake'}
          onClick={() =>
            act('toggle_freeze', { ckey: p.ckey, char_name: p.char_name })
          }
        >
          {p.frozen ? 'Thaw' : 'Freeze'}
        </Button>
        <Button
          compact
          icon="clock"
          onClick={() =>
            act('adjust', { ckey: p.ckey, char_name: p.char_name })
          }
        >
          Adjust
        </Button>
        <Button
          compact
          color="good"
          icon="door-open"
          onClick={() =>
            act('release', { ckey: p.ckey, char_name: p.char_name })
          }
        >
          Release
        </Button>
      </Table.Cell>
      <Table.Cell>
        <Dropdown
          width="14rem"
          disabled={otherCells.length === 0}
          selected={selectedRef}
          options={otherCells.map((c) => ({
            value: c.ref,
            displayText: c.label,
          }))}
          onSelected={(value) => setSelectedRef(value)}
        />
        <Button
          compact
          ml={1}
          icon="truck-moving"
          disabled={!selectedRef}
          tooltip={
            otherCells.length === 0
              ? 'No other faction cell to transfer to.'
              : undefined
          }
          onClick={() =>
            act('transfer', {
              ckey: p.ckey,
              char_name: p.char_name,
              pod_ref: selectedRef,
            })
          }
        >
          Transfer
        </Button>
      </Table.Cell>
    </Table.Row>
  );
};

export const PrisonManagement = (props) => {
  const { data } = useBackend<PrisonManagementData>();
  const { faction_uid, faction_name, prisoners = [], cells = [] } = data;

  if (!faction_uid) {
    return (
      <NtosWindow width={550} height={400}>
        <NtosWindow.Content scrollable>
          <NoticeBox>
            This console is not linked to a faction. Tag it with a faction
            tagger tool first.
          </NoticeBox>
        </NtosWindow.Content>
      </NtosWindow>
    );
  }

  return (
    <NtosWindow width={750} height={400}>
      <NtosWindow.Content scrollable>
        <Section title={`${faction_name ?? faction_uid} -- Prison Management`}>
          {prisoners.length === 0 ? (
            <Box italic color="label">
              No one is currently imprisoned.
            </Box>
          ) : (
            <Table>
              <Table.Row header>
                <Table.Cell>Name</Table.Cell>
                <Table.Cell>Sentence</Table.Cell>
                <Table.Cell>Status</Table.Cell>
                <Table.Cell />
                <Table.Cell>Transfer To</Table.Cell>
              </Table.Row>
              {prisoners.map((p) => (
                <PrisonerRow
                  key={`${p.ckey}|${p.char_name}`}
                  prisoner={p}
                  cells={cells}
                />
              ))}
            </Table>
          )}
        </Section>
      </NtosWindow.Content>
    </NtosWindow>
  );
};
