/*   
 * Placa-de-aprendizaje.asm
 * Trabajo practico de Laboratorio de microprocesadores 86.07
 * 1er cuatrimestre de 2016 - FIUBA
 * Autor: Alan Decurnex (85409)
 */ 

.INCLUDE "m2560def.inc"			//Incluye definición archivos ATMEGA2560

; ***** DEFINICION DE CONSTANTES ***************************************************************
; se mide desde ADMUX_INICIO hasta ADMUX_FIN, 8 pines en total si mido desde A0 hasta A7
.equ	ADMUX_INICIO = 0x00 ; (codigo implememtado para 5 bits de MUX) desde A0
.equ	ADMUX_FIN	 = 0x07 ; hasta A7

.equ	MASCARA_ADMUX = 0x17 ; mascara para leer los 5 bits del MUX
.equ	INICIO_DE_TRAMA = 0x5A ; inicio de trama del codigo de checksum

; constantes para la medicion desde A0
.equ	A0_limite_superior_H = 0x02 ; superior 3.3 V, 675, 0x02A3
.equ	A0_limite_superior_L = 0xA3
.equ	A0_limite_inferior_H = 0x01 ; inferior 1.7 V, 348, 0x015C
.equ	A0_limite_inferior_L = 0x5C

; constantes para la medicion desde A1
.equ	A1_limite_superior_H = 0x00 ; superior 0x0036; decimal 54; 26,39 grados centigrados 
.equ	A1_limite_superior_L = 0x36 ;							   (54*5*100/1023)
.equ	A1_limite_inferior_H = 0x00 ; inferior 0x0033; decimal 51; 24,92 grados centigrados
.equ	A1_limite_inferior_L = 0x33 ;							   (51*5*100/1023)

; constantes para la medicion desde A2
.equ	A2_maximo_H = 0x00 ;  3.3 V, 675, 0x02A3
.equ	A2_maximo_L = 0x33


; ***** DEFINICION DE REGISTROS ****************************************************************
.def	checksum	= r24; Cyclic Redundancy Check

; ESTADO - registro encargado de registrar el estado actual del programa mediante flags
.def	ESTADO	= r25
; bit 0 = Flag que se activa al final de las mediciones

; ***** BIT DEFINITIONS ************************************************************************
.equ	FIN_DE_MEDICIONES	= 0	; Flag que se activa al final de las mediciones

; definiciones de los puertos de los actuadores de las mediciones
; salen todas por el puerto B

.equ	Pin_A0	= 7 ; se plantea de forma inversa para aprovechar el led del arduino
.equ	Pin_A1	= 6
.equ	Pin_A2	= 5
.equ	Pin_A3	= 4
.equ	Pin_A4	= 3
.equ	Pin_A5	= 2
.equ	Pin_A6	= 1
.equ	Pin_A7	= 0

.equ	PORT_A0 = PORTB
.equ	PORT_A1 = PORTB
.equ	PORT_A2 = PORTB
.equ	PORT_A3 = PORTB
.equ	PORT_A4 = PORTB
.equ	PORT_A5 = PORTB
.equ	PORT_A6 = PORTB
.equ	PORT_A7 = PORTB

.equ	DDR_A0 = DDRB
.equ	DDR_A1 = DDRB
.equ	DDR_A2 = DDRB
.equ	DDR_A3 = DDRB
.equ	DDR_A4 = DDRB
.equ	DDR_A5 = DDRB
.equ	DDR_A6 = DDRB
.equ	DDR_A7 = DDRB


; ***** PRINCIPAL ******************************************************************************
;Se abre un segmento de datos para definir variables
.dseg 
.org	SRAM_START // 0x200

; Definición de variables en la zona de memoria de uso general
muestreo: 	.byte	2 ; Variable que guarda el muestreo de la medicion actual (2 bytes)

;Se abre un segmente de código flash para escribir instrucciones o tablas.
.cseg
.ORG $00
RJMP RESET			// Reset

; interrupcion por conversion ADC completa
.org	ADCCaddr		; definido en m2560def.inc (0x003a)
rjmp	ISR_CONV_ADC_COMPLETA

.ORG INT_VECTORS_SIZE // salteo el vector de interrupciones

RESET:
	// mueve el stack pointer al final de la RAM para maximizar el espacio de STACK
	LDI R16,LOW(RAMEND)
	OUT SPL,R16
	LDI R16,HIGH(RAMEND)
	OUT SPH,R16
	
	rcall inicializar_puertos
	rcall inicializar_USART
	clr ESTADO ; inicializa estado

reinicio_mediciones:
	ldi checksum, INICIO_DE_TRAMA ; sumo el inicio de trama al checksum

	ldi r16, INICIO_DE_TRAMA
	rcall USART_Transmit ; transmito el inicio de trama
	rcall ADC_Primera_Medicion ; configuro y comienzo primera medicion

principal:
	sbrs ESTADO, FIN_DE_MEDICIONES
	rjmp principal

	; leo la medicion actual
	lds		r20, muestreo
	lds		r16, muestreo+1
	
	rcall procesar_medicion ; proceso la medicion

	andi ESTADO, ~(1<<FIN_DE_MEDICIONES) ; limpio el flag de FIN_DE_MEDICIONES

	; sumo la medicion actual al checksum
	add checksum, r20
	add checksum, r16

	; envio la medicion actual
	rcall USART_Transmit
	mov r16, r20
	rcall USART_Transmit

	; me fijo si es la ultima medicion
	lds	r16,ADMUX
	ldi r17, MASCARA_ADMUX
	and r17, r16 ; hago una mascara para solo quedarme con el MUX4:0
	cpi r17, ADMUX_FIN	; ultimo pin a leer
	breq enviar_fin_de_trama

	inc r16			; convierto desde el siguiente pin
	sts	ADMUX,r16	; escribe reg. ADMUX de configuración del ADC

	; envio a medir la siguiente conversion
	lds	r16,ADCSRA
	ori r16,(1<<ADSC); escribo ADSC en uno para iniciar siguiente conversion.
	sts ADCSRA,r16

	rjmp principal

enviar_fin_de_trama:
	neg checksum
	mov r16, checksum
	rcall USART_Transmit
	rjmp reinicio_mediciones

; inicializa los puertos utilizados, el puerto F como entradas analogicas y el B como salidas de los actuadores, con todas sus salidas en cero.	
inicializar_puertos:
	ldi r16,0x00
	; se mide desde el puerto F
	out DDRF,r16 ;configura todo el puerto F como entradas (analogicas)

	; control de salidas correspondientes a los valores medidos
	ldi r16,0xFF

	; configura los pines de salida de los actuadores de las mediciones
	sbi DDR_A0, Pin_A0
	sbi DDR_A1, Pin_A1
	sbi DDR_A2, Pin_A2
	sbi DDR_A3, Pin_A3
	sbi DDR_A4, Pin_A4
	sbi DDR_A5, Pin_A5
	sbi DDR_A6, Pin_A6
	sbi DDR_A7, Pin_A7

	; coloco por defecto las salidas en cero 
	cbi PORT_A0, Pin_A0
	cbi PORT_A1, Pin_A1
	cbi PORT_A2, Pin_A2
	cbi PORT_A3, Pin_A3
	cbi PORT_A4, Pin_A4
	cbi PORT_A5, Pin_A5
	cbi PORT_A6, Pin_A6
	cbi PORT_A7, Pin_A7

; rutina de inicializacion del USART, carga valores para un Baud Rate correspondiente y llama a la rutina USART_Init
inicializar_USART:
	; configuro baud rate de 250k (ver tabla pagina 226 de la datasheet)  error = 0%
	clr r17    
	ldi r16, 7
	rcall USART_Init ; inicializo USART
	ret

; rutina que configura la primera medicion del ADC segun el valor de ADMUX_INICIO, y envia a medir.
ADC_Primera_Medicion:	
	clr r26
	cli ; SREG<I>=0 interrupciones globales deshabilitadas
	; importante, la seleccion del MUX siempre debe hacerse ANTES de iniciar la conversion 
	; (puede hacerse durante la conversion anterior despues de que baje ADIF)

	ldi	r16,(0<<REFS1)|(1<<REFS0)|(0<<ADLAR)|ADMUX_INICIO ; ADMUX son los bits bajos, 4:0
		; (0<<REFS1)|(1<<REFS0): Referencia interna AVCC (5V)
		; (0<<ADLAR): Ajuste a derecha del resultado
		; (0<<MUX4)|(0<<MUX3)|(0<<MUX2)|(0<<MUX1)|(0<<MUX0): Convierto la tensión desde PF0 (ADC0)
	sts	ADMUX,r16	; escribe reg. ADMUX de configuración del ADC

	ldi	r16,(0<<MUX5)|(0<<ADTS2)|(0<<ADTS1)|(0<<ADTS0) ; los demas bits los dejo en cero
		; (0<<MUX5): para los canales F0:7 debe valer 0, de F8:15 debe valer 1
		; (0<<ADTS2)|(0<<ADTS1)|(0<<ADTS0): Free runing
	sts	ADCSRB,r16	; escribe reg. B de configuración del ADC

	ldi r16,(1<<ADEN)|(1<<ADSC)|(0<<ADATE)|(0<<ADIF)|(1<<ADIE)|(1<<ADPS2)|(1<<ADPS1)|(1<<ADPS0)
		; (1<<ADEN): Habilita el ADC
		; (1<<ADSC): Pedido de 1er conversión (inicia)
		; (0<<ADATE):  permite el auto triggering, por ejemplo: conversion continua 
		; (si esta en cero solo inicia medicion con ADSC en 1)
		; (0<<ADIF): Limpio posible interrupcion falsa
		; (1<<ADIE): Interrumpe cada vez que termina una conversión	
		; (1<<ADPS2)|(1<<ADPS1)|(1<<ADPS0): 16MHz/128 = 125 kHz                
			; primera conversion en (25/125k) = 200 uSeg
			; siguiente conversion en (13/125k) = 104 uSeg
	sts ADCSRA,r16		; escribe reg. A de configuración del ADC / se inicia primera conversion

	sei ; habilito interrupciones globales
	ret

; procesa la medicion actual
procesar_medicion:

	; me fijo cual medicion es
	lds	r18,ADMUX
	ldi r17, MASCARA_ADMUX
	and r17, r18 ; hago una mascara para solo quedarme con el MUX4:0
	
	; switch 
	cpi r17, 0
	breq procesar_A0
	cpi r17, 1
	breq procesar_A1
	cpi r17, 2
	breq procesar_A2
	cpi r17, 3
	breq procesar_A3
	cpi r17, 4
	breq procesar_A4
	cpi r17, 5
	breq procesar_A5
	cpi r17, 6
	breq procesar_A6
	cpi r17, 7
	breq procesar_A7
	rjmp default

procesar_A0:
	; ventana = [A0_limite_inferior, A0_limite_superior]
	; si el valor no esta incluido en la ventana, habilita la salida.

	; comparo con limite inferior
	ldi r17, A0_limite_inferior_H ; cargo en r17 el valor alto para poder usar cpc
	cpi r20, A0_limite_inferior_L ; comparo los bits bajos
	cpc r16, r17 ; comparo los bits altos
	brlo A0_afuera_de_ventana ; afuera por limite inferior

	; comparo con limite superior
	ldi r17, A0_limite_superior_H
	cpi r20, A0_limite_superior_L ; comparo los bits bajos
	cpc r16, r17 ; comparo los bits altos
	brlo A0_adentro_de_ventana
	breq A0_adentro_de_ventana
	; afuera por limite superior

A0_afuera_de_ventana:
	sbi PORT_A0, Pin_A0 ; prende el pin correspondiente
	rjmp fin_procesar_A0

A0_adentro_de_ventana:
	cbi PORT_A0, Pin_A0 ; apago el pin correspondiente

fin_procesar_A0:
	rjmp fin_switch

procesar_A1: // procesamiento de una ventana de temperatura
	; ventana  = [A1_limite_inferior, A1_limite_superior]
	; si el valor es superior a A1_limite_superior, habilito la salida
	; si el valor es inferior a A1_limite_inferior, deshabilito la salida
	; si el valor esta incluido en la ventana, no hago nada

	; comparo con limite inferior
	ldi r17, A1_limite_inferior_H
	cpi r20, A1_limite_inferior_L ; comparo los bits bajos
	cpc r16, r17 ; comparo los bits altos
	brlo A1_menor_a_ventana ; afuera por limite inferior

	; comparo con limite superior
	ldi r17, A1_limite_superior_H
	cpi r20, A1_limite_superior_L ; comparo los bits bajos
	cpc r16, r17 ; comparo los bits altos
	brlo A1_adentro_de_ventana
	breq A1_adentro_de_ventana

	; si llega aca es porque esta afuera por limite superior

A1_mayor_a_ventana:
	sbi PORT_A1, Pin_A1 ; prende el pin correspondiente
	rjmp fin_procesar_A1

A1_menor_a_ventana:
	cbi PORT_A1, Pin_A1 ; apago el pin correspondiente
	rjmp fin_procesar_A1

A1_adentro_de_ventana: ; en este caso no hago nada

fin_procesar_A1:
	rjmp fin_switch

procesar_A2:
; si el valor medido supera el maximo, se habilita la salida

	; comparo con el maximo
	ldi r17, A2_maximo_H
	cpi r20, A2_maximo_L ; comparo los bits bajos
	cpc r16, r17 ; comparo los bits altos
	brlo A2_menor_o_igual_al_maximo ; menor al maximo
	breq A2_menor_o_igual_al_maximo ; igual al maximo
	; mayor al maximo

A2_mayor_al_maximo:
	sbi PORT_A2, Pin_A2 ; prende el pin correspondiente
	rjmp fin_procesar_A2

A2_menor_o_igual_al_maximo:
	cbi PORT_A2, Pin_A2 ; apago el pin correspondiente

fin_procesar_A2:
	rjmp fin_switch

procesar_A3:
	rjmp fin_switch
procesar_A4:
	rjmp fin_switch
procesar_A5:
	rjmp fin_switch
procesar_A6:
	rjmp fin_switch
procesar_A7:
	rjmp fin_switch
default: 
	/* no hago nada*/
fin_switch:
	ret


///// IMPLEMENTACION DE FUNCIONES DE USART, segun Datasheet ///////////

; inicializa el USART
USART_Init:
	; Set baud rate
	sts UBRR0H, r17
	sts UBRR0L, r16

	ldi r16, (1<<U2X0) ; dobla la velocidad de transmision en modo asincronico
	sts UCSR0A, r16

	; Enable receiver and transmitter
	ldi r16, (1<<RXEN0)|(1<<TXEN0) ;  (0<<UCSZ02)
	sts UCSR0B, r16

	; Set frame format: 8data, 1stop bit
	ldi r16, (1<<UCSZ01)|(1<<UCSZ00); asincronico, paridad disable, 1 stop bit, 
	                                ; 8 data (011, el tercer bit esta en UCSR0B)
	sts UCSR0C, r16
	ret

; envia el dato que esta en r16 por serie
USART_Transmit:
	; Wait for empty transmit buffer
	lds r17, UCSR0A
	sbrs r17, UDRE0 ; me fijo si esta vacio el buffer de salida
	rjmp USART_Transmit

	; Put data (r16) into buffer, sends the data
	sts UDR0, r16
	ret

; lee el siguiente valor serie y lo almacena en r16
USART_Receive:
	; Wait for data to be received
	lds r17, UCSR0A
	sbrs r17, RXC0 ; se fija si llego nuevo dato
	rjmp USART_Receive

	; Get and return received data from buffer
	lds r16, UDR0
	ret

/////////// FIN USART //////////////////////////////////////////////////////////////////


;-------------------------------------------------------------------------
; Rutina de Servicio de Interrupción (ISR) del conversor ADC
;-------------------------------------------------------------------------
ISR_CONV_ADC_COMPLETA:
; limpia automaticamente el bit ADIF (especificado en Datasheet)
; copio el resultado de la conversión a la variable "muestreo"
	push r20
	push r21
	lds		r20,ADCL		; se lee 1ro el byte bajo
	lds		r21,ADCH		; y luego el alto

	sts		muestreo,r20
	sts		muestreo+1,r21

	ori ESTADO, (1<<FIN_DE_MEDICIONES) ; seteo el flag FIN_DE_MEDICIONES

	pop r21
	pop r20
	reti
