import { Box, Button, LabeledList, NoticeBox } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useBackend } from '../backend';
import { NtosWindow } from '../layouts';

type PrisonPodData = {
  occupant_name: string | null;
  nopower: BooleanLike;
  broken: BooleanLike;
  faction_name: string | null;
  can_imprison: BooleanLike;
  locked: BooleanLike;
  imprisoned: BooleanLike;
  indefinite: BooleanLike;
  remaining_seconds: number;
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
    occupant_name,
    nopower,
    broken,
    faction_name,
    can_imprison,
    locked,
    imprisoned,
    indefinite,
    remaining_seconds,
  } = data;

  return (
    <NtosWindow width={420} height={360}>
      <NtosWindow.Content scrollable>
        {!!broken && <NoticeBox danger>This unit is damaged.</NoticeBox>}
        {!!nopower && <NoticeBox danger>This unit has no power.</NoticeBox>}
        <LabeledList>
          <LabeledList.Item label="Faction">
            {faction_name ?? 'Unassigned'}
          </LabeledList.Item>
          <LabeledList.Item label="Occupant">
            {occupant_name ?? 'Empty'}
          </LabeledList.Item>
          {!!occupant_name && (
            <>
              <LabeledList.Item label="Sentence">
                {imprisoned
                  ? indefinite
                    ? 'Indefinite'
                    : formatRemaining(remaining_seconds)
                  : 'Not imprisoned'}
              </LabeledList.Item>
              {!!imprisoned && (
                <LabeledList.Item label="Cell Status">
                  <Box color={locked ? 'bad' : 'good'} inline>
                    {locked ? 'Locked' : 'Unlocked (parole)'}
                  </Box>
                </LabeledList.Item>
              )}
            </>
          )}
        </LabeledList>
        <Box mt={1}>
          {!imprisoned ? (
            <Button
              icon="lock"
              color="bad"
              disabled={!occupant_name || !can_imprison}
              tooltip={
                !can_imprison
                  ? 'Must be tagged to a faction before it can imprison anyone.'
                  : 'Imprison the current occupant'
              }
              onClick={() => act('imprison')}
            >
              Imprison
            </Button>
          ) : (
            <>
              <Button
                icon="door-open"
                color="good"
                onClick={() => act('release')}
              >
                Release
              </Button>
              <Button
                icon={locked ? 'unlock' : 'lock'}
                ml={1}
                onClick={() => act('toggle_lock')}
              >
                {locked ? 'Unlock' : 'Lock'}
              </Button>
            </>
          )}
        </Box>
      </NtosWindow.Content>
    </NtosWindow>
  );
};
