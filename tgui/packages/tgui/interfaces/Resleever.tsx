import { Box, Button, LabeledList, NoticeBox, Section } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useBackend } from '../backend';
import { Window } from '../layouts';

type ResleeverData = {
  lace_name: string | null;
  lace_occupied: BooleanLike;
  /** Name of the body physically placed inside THIS machine, but only when
   * it's a valid (mindless) resleeve target -- null if empty or already
   * holding somebody with a mind of their own. */
  body_name: string | null;
  occupied: BooleanLike;
  can_resleeve: BooleanLike;
  linked_pod: BooleanLike;
  pod_occupied: BooleanLike;
  pod_clone_name: string | null;
  pod_growing: BooleanLike;
  can_order_clone: BooleanLike;
  /** 0 when this server has cloning set to free (CLONING_COSTS_CREDITS). */
  clone_cost: number;
  clone_payer: string | null;
};

export const Resleever = (props) => {
  const { act, data } = useBackend<ResleeverData>();
  const {
    lace_name,
    lace_occupied,
    body_name,
    occupied,
    can_resleeve,
    linked_pod,
    pod_occupied,
    pod_clone_name,
    pod_growing,
    can_order_clone,
    clone_cost,
    clone_payer,
  } = data;

  return (
    <Window width={420} height={480} title="Resleeving Machine">
      <Window.Content scrollable>
        <Section title="Neural Lace">
          <LabeledList>
            <LabeledList.Item label="Inserted">
              {lace_name ? (
                <Box color={lace_occupied ? 'good' : 'average'}>
                  {lace_name} -- {lace_occupied ? 'consciousness present' : 'empty'}
                </Box>
              ) : (
                <Box color="label">No lace inserted.</Box>
              )}
            </LabeledList.Item>
          </LabeledList>
          <Button
            fluid
            mt={1}
            icon="eject"
            disabled={!lace_name}
            onClick={() => act('eject_lace')}
          >
            Eject Lace
          </Button>
        </Section>

        <Section title="Occupant">
          <LabeledList>
            <LabeledList.Item label="Body">
              {!occupied ? (
                <Box color="label">
                  Empty. Drag a body onto this machine, or grab-and-click it,
                  to place one inside.
                </Box>
              ) : body_name ? (
                <Box color="good">{body_name}</Box>
              ) : (
                <Box color="bad">Has a mind of their own -- not resleevable.</Box>
              )}
            </LabeledList.Item>
          </LabeledList>
          <Button
            fluid
            mt={1}
            icon="eject"
            disabled={!occupied}
            onClick={() => act('eject_occupant')}
          >
            Eject Occupant
          </Button>
        </Section>

        <Section title="Cloning Pod">
          {!linked_pod ? (
            <NoticeBox>
              No cloning pod linked. Use a multitool on the pod, then on this
              machine.
            </NoticeBox>
          ) : (
            <LabeledList>
              <LabeledList.Item label="Pod">
                {pod_growing ? (
                  <Box color="average">Growing...</Box>
                ) : pod_occupied ? (
                  <Box color="good">Clone ready: {pod_clone_name}</Box>
                ) : (
                  <Box color="label">Empty.</Box>
                )}
              </LabeledList.Item>
              {pod_occupied && !pod_growing && (
                <LabeledList.Item label="Note">
                  <Box color="label">
                    Carry the clone over and place it in this machine to
                    resleeve into it.
                  </Box>
                </LabeledList.Item>
              )}
              {clone_cost > 0 && (
                <LabeledList.Item label="Billed to">
                  {clone_payer}
                </LabeledList.Item>
              )}
            </LabeledList>
          )}
          <Button
            fluid
            mt={1}
            icon="dna"
            disabled={!can_order_clone}
            tooltip={
              !linked_pod
                ? 'No cloning pod linked.'
                : pod_growing
                  ? 'A clone is already growing.'
                  : pod_occupied
                    ? 'The linked pod already holds a body.'
                    : !lace_name
                      ? 'Insert the neural lace to clone from.'
                      : undefined
            }
            onClick={() => act('order_clone')}
          >
            {clone_cost > 0
              ? `Order Clone (${clone_cost.toLocaleString()} cr)`
              : 'Order Clone'}
          </Button>
        </Section>

        <Section title="Resleeve">
          <Button
            fluid
            icon="syringe"
            color="good"
            disabled={!can_resleeve}
            tooltip={
              !lace_name
                ? 'No lace inserted.'
                : !lace_occupied
                  ? 'That lace carries no consciousness.'
                  : !body_name
                    ? 'No resleevable body inside this machine.'
                    : undefined
            }
            onClick={() => act('resleeve')}
          >
            Begin Resleeve
          </Button>
        </Section>
      </Window.Content>
    </Window>
  );
};
