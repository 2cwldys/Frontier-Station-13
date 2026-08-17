import { Box, Button, LabeledList, NoticeBox, Section } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useBackend } from '../backend';
import { Window } from '../layouts';

type ResleeverData = {
  lace_name: string | null;
  lace_occupied: BooleanLike;
  body_name: string | null;
  can_resleeve: BooleanLike;
  linked_pod: BooleanLike;
  pod_occupied: BooleanLike;
  pod_clone_name: string | null;
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
    can_resleeve,
    linked_pod,
    pod_occupied,
    pod_clone_name,
    can_order_clone,
    clone_cost,
    clone_payer,
  } = data;

  return (
    <Window width={420} height={460} title="Resleeving Machine">
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

        <Section title="Cloning Pod">
          {!linked_pod ? (
            <NoticeBox>
              No cloning pod linked. Use a multitool on the pod, then on this
              machine.
            </NoticeBox>
          ) : (
            <LabeledList>
              <LabeledList.Item label="Pod">
                {pod_occupied ? (
                  <Box color="good">Clone ready: {pod_clone_name}</Box>
                ) : (
                  <Box color="label">Empty.</Box>
                )}
              </LabeledList.Item>
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

        <Section title="Target Body">
          <LabeledList>
            <LabeledList.Item label="Selected">
              {body_name || <Box color="label">None.</Box>}
            </LabeledList.Item>
          </LabeledList>
          <Button
            fluid
            mt={1}
            icon="user-plus"
            onClick={() => act('set_target')}
          >
            Select Body
          </Button>
          {!!body_name && (
            <Button fluid mt={1} icon="times" onClick={() => act('clear_target')}>
              Clear Selection
            </Button>
          )}
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
                    ? 'No target body selected.'
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
